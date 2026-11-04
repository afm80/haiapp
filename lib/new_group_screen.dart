import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'chat_screen.dart';
import 'contacts_service.dart';
import 'utils.dart';
import 'widgets.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _name = TextEditingController();
  final _selected = <String, String>{}; // uid -> name
  bool _creating = false;

  Future<void> _create() async {
    final title = _name.text.trim();
    if (title.isEmpty) {
      _snack('اكتب اسم المجموعة');
      return;
    }
    if (_selected.isEmpty) {
      _snack('اختر عضواً واحداً على الأقل');
      return;
    }
    setState(() => _creating = true);
    try {
      final uid = currentUser.uid;
      final ref = fs.collection('chats').doc();
      await ref.set({
        'isGroup': true,
        'groupName': title,
        'createdBy': uid,
        'admins': [uid],
        'participants': [uid, ..._selected.keys],
        'names': {uid: currentUser.displayName ?? '', ..._selected},
        'lastMessage': 'تم إنشاء المجموعة',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': uid,
        'lastSenderName': currentUser.displayName ?? '',
      });
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: ref.id)));
    } catch (_) {
      _snack('تعذر إنشاء المجموعة');
      if (mounted) setState(() => _creating = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مجموعة جديدة')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(
                  labelText: 'اسم المجموعة',
                  prefixIcon: Icon(Icons.group),
                  border: OutlineInputBorder()),
            ),
          ),
          if (_selected.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final e in _selected.entries)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: Chip(
                        label: Text(e.value),
                        onDeleted: () => setState(() => _selected.remove(e.key)),
                      ),
                    ),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('إضافة أعضاء', style: TextStyle(fontWeight: FontWeight.bold))),
          ),
          Expanded(
            child: ContactsView(
              builder: (context, users) {
                if (users.isEmpty) {
                  return const Center(child: Text('لا توجد جهات اتصال مسجلة لإضافتها'));
                }
                return ListView(
                  children: [
                    for (final m in users)
                      CheckboxListTile(
                        value: _selected.containsKey(m.uid),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected[m.uid] = m.name;
                          } else {
                            _selected.remove(m.uid);
                          }
                        }),
                        secondary: Avatar(photo: m.user['photo'] as String?, name: m.name),
                        title: Text(m.name),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        onPressed: _creating ? null : _create,
        child: _creating
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.check),
      ),
    );
  }
}
