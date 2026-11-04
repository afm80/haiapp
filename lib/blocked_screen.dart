import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'utils.dart';
import 'widgets.dart';

class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المحظورون')),
      body: UserBuilder(
        uid: currentUser.uid,
        builder: (context, me) {
          final blocked = List<String>.from(me['blocked'] ?? const []);
          if (blocked.isEmpty) return const Center(child: Text('لا يوجد مستخدمون محظورون'));
          return ListView(
            children: [
              for (final id in blocked)
                UserBuilder(
                  uid: id,
                  builder: (_, u) => ListTile(
                    leading: Avatar(
                        photo: u['photo'] as String?, name: (u['name'] ?? '?').toString()),
                    title: Text((u['name'] ?? '').toString()),
                    trailing: TextButton(
                      onPressed: () => fs.collection('users').doc(currentUser.uid).update({
                        'blocked': FieldValue.arrayRemove([id])
                      }),
                      child: const Text('إلغاء الحظر'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
