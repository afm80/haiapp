import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'actions.dart';
import 'utils.dart';
import 'widgets.dart';

/// تحويل رسالة إلى محادثة أخرى
class ForwardScreen extends StatelessWidget {
  final Map<String, dynamic> message;
  const ForwardScreen({super.key, required this.message});

  String _title(Map<String, dynamic> d) {
    if (d['isSaved'] == true) return 'الرسائل المحفوظة';
    if (d['isGroup'] == true) return (d['groupName'] ?? 'مجموعة').toString();
    final names = Map<String, dynamic>.from(d['names'] ?? {});
    final other = (d['participants'] as List)
        .firstWhere((id) => id != currentUser.uid, orElse: () => '');
    return (names[other] ?? 'مستخدم').toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تحويل إلى...')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: fs
            .collection('chats')
            .where('participants', arrayContains: currentUser.uid)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs =
              snap.data!.docs.where((d) => d.data()['lastMessage'] != null).toList();
          if (docs.isEmpty) return const Center(child: Text('لا توجد محادثات'));
          return ListView(
            children: [
              for (final doc in docs)
                ListTile(
                  leading: Avatar(
                    photo: doc.data()['groupPhoto'] as String?,
                    name: _title(doc.data()),
                    isGroup: doc.data()['isGroup'] == true,
                  ),
                  title: Text(_title(doc.data())),
                  onTap: () async {
                    final parts = List<String>.from(doc.data()['participants'] ?? const []);
                    await sendToChat(doc.id, parts, {...message, 'forwarded': true},
                        previewOf(message));
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('تم التحويل')));
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
