import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
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
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      fs.collection('users').snapshots();
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final users = snap.data!.docs
              .where((d) => !widget.existing.contains(d.id))
              .where((d) => (d['name'] ?? '').toString().trim().isNotEmpty)
              .toList();
          if (users.isEmpty) return const Center(child: Text('لا يوجد مستخدمون لإضافتهم'));
          return ListView(
            children: [
              for (final u in users)
                CheckboxListTile(
                  value: _selected.containsKey(u.id),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected[u.id] = u['name'];
                    } else {
                      _selected.remove(u.id);
                    }
                  }),
                  secondary: Avatar(photo: u['photo'] as String?, name: u['name']),
                  title: Text(u['name']),
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
