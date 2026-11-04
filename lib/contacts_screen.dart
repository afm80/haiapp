import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'actions.dart';
import 'app_colors.dart';
import 'new_group_screen.dart';
import 'utils.dart';
import 'widgets.dart';

enum ContactsMode { chat, call }

class ContactsScreen extends StatefulWidget {
  final ContactsMode mode;
  const ContactsScreen({super.key, this.mode = ContactsMode.chat});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      fs.collection('users').snapshots();
  final _search = TextEditingController();
  bool _searching = false;
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCall = widget.mode == ContactsMode.call;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                    hintText: 'بحث عن اسم...',
                    hintStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none),
                onChanged: (v) => setState(() => _q = v.trim()),
              )
            : Text(isCall ? 'اختر جهة اتصال' : 'محادثة جديدة'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _search.clear();
              _q = '';
            }),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final users = snap.data!.docs
              .where((d) => d.id != currentUser.uid)
              .where((d) => (d['name'] ?? '').toString().trim().isNotEmpty)
              .where((d) => _q.isEmpty || d['name'].toString().contains(_q))
              .toList();
          return ListView(
            children: [
              if (!isCall && _q.isEmpty)
                ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: AppColors.accent,
                      child: Icon(Icons.group_add, color: Colors.white)),
                  title: const Text('مجموعة جديدة'),
                  onTap: () => Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const NewGroupScreen())),
                ),
              if (users.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('ما فيه مستخدمين بعد')),
                ),
              for (final u in users)
                ListTile(
                  leading: Avatar(photo: u['photo'] as String?, name: u['name'], radius: 24),
                  title: Text(u['name']),
                  subtitle: Text((u.data()['about'] ?? '').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: isCall
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.call, color: AppColors.primary),
                              onPressed: () => startCall(context,
                                  calleeIds: [u.id], title: u['name'], video: false),
                            ),
                            IconButton(
                              icon: const Icon(Icons.videocam, color: AppColors.primary),
                              onPressed: () => startCall(context,
                                  calleeIds: [u.id], title: u['name'], video: true),
                            ),
                          ],
                        )
                      : null,
                  onTap: isCall
                      ? null
                      : () => openDirectChat(context, u.id, u['name'], replace: true),
                ),
            ],
          );
        },
      ),
    );
  }
}
