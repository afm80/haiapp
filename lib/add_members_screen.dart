import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'contacts_service.dart';
import 'utils.dart';
import 'widgets.dart';

class AddMembersScreen extends StatefulWidget {
  final String chatId;
  final List<String> existing;
  const AddMembersScreen({super.key, required this.chatId, required this.existing});

  @override
  State<AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<AddMembersScreen> {
  final _selected = <String, String>{};
  bool _saving = false;

  Future<void> _add() async {
    if (_selected.isEmpty) return;
    setState(() => _saving = true);
    await fs.collection('chats').doc(widget.chatId).update({
      'participants': FieldValue.arrayUnion(_selected.keys.toList()),
      for (final e in _selected.entries) 'names.${e.key}': e.value,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة أعضاء')),
      body: ContactsView(
        builder: (context, all) {
          final users = all.where((m) => !widget.existing.contains(m.uid)).toList();
          if (users.isEmpty) return const Center(child: Text('لا يوجد مستخدمون لإضافتهم'));
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        onPressed: _saving ? null : _add,
        child: const Icon(Icons.check),
      ),
    );
  }
}
