import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'chat_screen.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!;
    final stream = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: me.uid)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('HaiApp'),
        actions: [
          IconButton(
            tooltip: 'تسجيل خروج',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('تعذر تحميل المحادثات'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs.toList()
            ..sort((a, b) {
              final ta = (a['lastMessageAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
              final tb = (b['lastMessageAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
              return tb.compareTo(ta);
            });
          if (docs.isEmpty) {
            return const Center(child: Text('ما عندك محادثات.\nاضغط + لبدء محادثة'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final names = Map<String, dynamic>.from(d['names'] ?? {});
              final otherId = (d['participants'] as List)
                  .firstWhere((id) => id != me.uid, orElse: () => me.uid);
              final title = names[otherId] ?? 'مستخدم';
              final ts = d['lastMessageAt'] as Timestamp?;
              return ListTile(
                leading: CircleAvatar(
                  child: Text(title.toString().characters.first),
                ),
                title: Text(title),
                subtitle: Text(d['lastMessage'] ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: ts == null
                    ? null
                    : Text(DateFormat('HH:mm').format(ts.toDate()),
                        style: Theme.of(context).textTheme.bodySmall),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ChatScreen(chatId: docs[i].id, title: title),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const UsersScreen())),
        child: const Icon(Icons.add_comment),
      ),
    );
  }
}

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  Future<void> _openChat(
      BuildContext context, String otherId, String otherName) async {
    final me = FirebaseAuth.instance.currentUser!;
    final ids = [me.uid, otherId]..sort();
    final chatId = ids.join('_');
    await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
      'participants': ids,
      'names': {
        me.uid: me.displayName ?? 'مستخدم',
        otherId: otherName,
      },
    }, SetOptions(merge: true));
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => ChatScreen(chatId: chatId, title: otherName)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!;
    return Scaffold(
      appBar: AppBar(title: const Text('محادثة جديدة')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snap.data!.docs.where((d) => d.id != me.uid).toList();
          if (users.isEmpty) {
            return const Center(child: Text('ما فيه مستخدمين ثانيين بعد'));
          }
          return ListView(
            children: [
              for (final u in users)
                ListTile(
                  leading: CircleAvatar(
                      child: Text((u['name'] ?? '?').toString().characters.first)),
                  title: Text(u['name'] ?? ''),
                  subtitle: Text(u['email'] ?? ''),
                  onTap: () => _openChat(context, u.id, u['name'] ?? 'مستخدم'),
                ),
            ],
          );
        },
      ),
    );
  }
}
