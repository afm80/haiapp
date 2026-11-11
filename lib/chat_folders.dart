import 'package:flutter/material.dart';

import 'utils.dart';

/// إضافة محادثات محددة إلى مجلد (أو إنشاء مجلد جديد) من شريط التحديد
Future<void> addChatsToFolder(BuildContext context, Set<String> chatIds) async {
  final ref = fs.collection('users').doc(currentUser.uid);
  final messenger = ScaffoldMessenger.of(context);
  List<Map<String, dynamic>> folders = [];
  try {
    final d = await ref.get();
    final raw = d.data()?['folders'];
    if (raw is List) {
      for (final f in raw) {
        if (f is Map) {
          folders.add({
            'id': (f['id'] ?? '').toString(),
            'name': (f['name'] ?? '').toString(),
            'chats': List<String>.from(f['chats'] ?? const []),
          });
        }
      }
    }
  } catch (_) {}
  if (!context.mounted) return;

  Future<void> save(List<Map<String, dynamic>> list) async {
    try {
      await ref.update({'folders': list});
      messenger.showSnackBar(const SnackBar(content: Text('تمت الإضافة إلى المجلد')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذر حفظ المجلد')));
    }
  }

  // لا مجلدات بعد: ننشئ أول مجلد ونضع فيه المحادثات
  if (folders.isEmpty) {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مجلد جديد'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: 'مثال: عمل، عائلة'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await save([
      {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': name,
        'chats': chatIds.toList(),
      }
    ]);
    return;
  }

  // اختيار مجلد موجود
  final chosen = <String>{};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('إضافة إلى مجلد'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in folders)
                CheckboxListTile(
                  value: chosen.contains(f['id']),
                  title: Text(f['name'] as String),
                  onChanged: (v) => setS(() {
                    if (v == true) {
                      chosen.add(f['id'] as String);
                    } else {
                      chosen.remove(f['id']);
                    }
                  }),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    ),
  );
  if (ok != true || chosen.isEmpty) return;
  await save([
    for (final f in folders)
      chosen.contains(f['id'])
          ? {
              ...f,
              'chats': {...(f['chats'] as List<String>), ...chatIds}.toList(),
            }
          : f
  ]);
}
