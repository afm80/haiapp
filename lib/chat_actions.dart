import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'utils.dart';

/// حذف محادثة (أو عدة محادثات) من حسابك فقط، مثل واتساب.
/// نسجّل وقت الحذف في clearedAt.<uid>: تختفي المحادثة وتظهر من جديد عند وصول رسالة أحدث.
/// يرجع true إذا تم الحذف.
Future<bool> deleteChatsConfirm(BuildContext context, Set<String> ids) async {
  final n = ids.length;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(n == 1 ? 'حذف المحادثة؟' : 'حذف $n محادثات؟'),
      content: const Text('ستُحذف الرسائل من حسابك فقط، ولن تتأثر محادثة الطرف الآخر.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('حذف', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    for (final id in ids) {
      await _purgeChat(id, currentUser.uid);
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذر حذف المحادثة')));
    }
    return false;
  }
}

/// حذف فعلي للمحادثة من حسابي:
/// - كل رسالة تُعلَّم "محذوفة عندي"؛ وإذا كان الباقون قد حذفوها أيضاً تُمسح نهائياً من قاعدة البيانات.
/// - المحادثة تختفي من قائمتي، وتعود فارغة إن وصلت رسالة جديدة.
Future<void> _purgeChat(String chatId, String uid) async {
  final chatRef = fs.collection('chats').doc(chatId);
  final chat = await chatRef.get();
  final parts = List<String>.from(chat.data()?['participants'] ?? const []);
  final others = parts.where((p) => p != uid).toList();
  final msgs = await chatRef.collection('messages').get();

  final ops = <void Function(WriteBatch)>[];
  var allGone = true;
  for (final m in msgs.docs) {
    final d = List<String>.from(m.data()['deletedFor'] ?? const []);
    final othersDone = others.every(d.contains);
    if (othersDone) {
      ops.add((b) => b.delete(m.reference));
    } else {
      allGone = false;
      if (!d.contains(uid)) {
        ops.add((b) => b.update(m.reference, {'deletedFor': FieldValue.arrayUnion([uid])}));
      }
    }
  }
  ops.add((b) => b.update(chatRef, {
        'clearedAt.$uid': FieldValue.serverTimestamp(),
        'unread.$uid': 0,
        'pinnedBy': FieldValue.arrayRemove([uid]),
        'archivedBy': FieldValue.arrayRemove([uid]),
        if (allGone) 'lastMessage': '',
      }));
  for (var i = 0; i < ops.length; i += 400) {
    final batch = fs.batch();
    for (final op in ops.skip(i).take(400)) {
      op(batch);
    }
    await batch.commit();
  }
}

/// حذف رسالة واحدة عندي: تُعلَّم محذوفة، وتُمسح نهائياً إذا حذفها الباقون أيضاً
Future<void> deleteMessageForMe(
    DocumentReference<Map<String, dynamic>> ref, List<String> participants) async {
  final uid = currentUser.uid;
  final snap = await ref.get();
  final d = List<String>.from(snap.data()?['deletedFor'] ?? const []);
  final othersDone = participants.where((p) => p != uid).every(d.contains);
  if (othersDone) {
    await ref.delete();
  } else {
    await ref.update({'deletedFor': FieldValue.arrayUnion([uid])});
  }
}

/// تثبيت/إلغاء تثبيت أو أرشفة/إلغاء أرشفة. field = pinnedBy أو archivedBy.
/// إن كانت كل المحادثات المحددة مفعّلة يُلغى التفعيل، وإلا يُفعَّل على الجميع.
Future<void> toggleChatFlag(Set<String> ids, String field) async {
  final uid = currentUser.uid;
  final docs = await Future.wait(ids.map((id) => fs.collection('chats').doc(id).get()));
  final allOn = docs.every(
      (d) => List<String>.from(d.data()?[field] ?? const []).contains(uid));
  final batch = fs.batch();
  for (final d in docs) {
    batch.update(d.reference, {
      field: allOn ? FieldValue.arrayRemove([uid]) : FieldValue.arrayUnion([uid]),
    });
  }
  await batch.commit();
}
