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
  final uid = currentUser.uid;
  try {
    final batch = fs.batch();
    for (final id in ids) {
      batch.update(fs.collection('chats').doc(id), {
        'clearedAt.$uid': FieldValue.serverTimestamp(),
        'unread.$uid': 0,
        'pinnedBy': FieldValue.arrayRemove([uid]),
        'archivedBy': FieldValue.arrayRemove([uid]),
      });
    }
    await batch.commit();
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذر حذف المحادثة')));
    }
    return false;
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
