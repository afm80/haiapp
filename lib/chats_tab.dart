import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'chat_screen.dart';
import 'utils.dart';
import 'widgets.dart';

class ChatsTab extends StatefulWidget {
  final ValueListenable<String> query;
  final bool archived;
  const ChatsTab({super.key, required this.query, this.archived = false});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = fs
      .collection('chats')
      .where('participants', arrayContains: currentUser.uid)
      .snapshots();

  String get _uid => currentUser.uid;

  bool _flag(Map<String, dynamic> d, String key) =>
      List<String>.from(d[key] ?? const []).contains(_uid);

  String _titleOf(Map<String, dynamic> d) {
    if (d['isGroup'] == true) return (d['groupName'] ?? 'مجموعة').toString();
    final names = Map<String, dynamic>.from(d['names'] ?? {});
    final otherId =
        (d['participants'] as List).firstWhere((id) => id != _uid, orElse: () => '');
    return (names[otherId] ?? 'مستخدم').toString();
  }

  int _millis(Map<String, dynamic> d) =>
      (d['lastMessageAt'] as Timestamp?)?.millisecondsSinceEpoch ??
      DateTime.now().millisecondsSinceEpoch;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: widget.query,
      builder: (context, q, _) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('تعذر تحميل المحادثات'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!.docs.where((d) => d.data()['lastMessage'] != null).toList();
          final archivedCount = all.where((d) => _flag(d.data(), 'archivedBy')).length;
          final docs = all
              .where((d) => _flag(d.data(), 'archivedBy') == widget.archived)
              .where((d) => q.isEmpty || _titleOf(d.data()).contains(q))
              .toList()
            ..sort((a, b) {
              final pa = _flag(a.data(), 'pinnedBy') ? 1 : 0;
              final pb = _flag(b.data(), 'pinnedBy') ? 1 : 0;
              if (pa != pb) return pb.compareTo(pa);
              return _millis(b.data()).compareTo(_millis(a.data()));
            });

          final showArchiveRow = !widget.archived && archivedCount > 0 && q.isEmpty;
          if (docs.isEmpty && !showArchiveRow) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  q.isNotEmpty
                      ? 'لا نتائج'
                      : (widget.archived
                          ? 'لا توجد محادثات مؤرشفة'
                          : 'ما عندك محادثات بعد.\nاضغط على زر المحادثة لبدء أول محادثة.'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: docs.length + (showArchiveRow ? 1 : 0),
            itemBuilder: (context, i) {
              if (showArchiveRow && i == 0) {
                return ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: const Text('المؤرشفة'),
                  trailing: Text('$archivedCount'),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ArchivedScreen())),
                );
              }
              return _tile(context, docs[i - (showArchiveRow ? 1 : 0)]);
            },
          );
        },
      ),
    );
  }

  void _menu(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final pinned = _flag(doc.data(), 'pinnedBy');
    final archived = _flag(doc.data(), 'archivedBy');
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(pinned ? 'إلغاء التثبيت' : 'تثبيت المحادثة'),
              onTap: () {
                Navigator.pop(ctx);
                doc.reference.update({
                  'pinnedBy': pinned
                      ? FieldValue.arrayRemove([_uid])
                      : FieldValue.arrayUnion([_uid])
                });
              },
            ),
            ListTile(
              leading: Icon(archived ? Icons.unarchive_outlined : Icons.archive_outlined),
              title: Text(archived ? 'إلغاء الأرشفة' : 'أرشفة المحادثة'),
              onTap: () {
                Navigator.pop(ctx);
                doc.reference.update({
                  'archivedBy': archived
                      ? FieldValue.arrayRemove([_uid])
                      : FieldValue.arrayUnion([_uid])
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final isGroup = d['isGroup'] == true;
    final unread = ((d['unread'] as Map?)?[_uid] ?? 0) as int;
    final pinned = _flag(d, 'pinnedBy');

    final lastSender = d['lastSenderId'];
    var preview = (d['lastMessage'] ?? '').toString();
    if (lastSender == _uid) {
      preview = 'أنت: $preview';
    } else if (isGroup && d['lastSenderName'] != null) {
      preview = '${d['lastSenderName']}: $preview';
    }

    Widget row(String title, String? photo) => ListTile(
          leading: Avatar(photo: photo, name: title, isGroup: isGroup, radius: 26),
          title: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(chatTime(d['lastMessageAt'] as Timestamp?),
                  style: TextStyle(
                      fontSize: 12,
                      color: unread > 0 ? AppColors.accent : Theme.of(context).hintColor)),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pinned)
                    Icon(Icons.push_pin, size: 16, color: Theme.of(context).hintColor),
                  if (unread > 0)
                    Container(
                      margin: const EdgeInsetsDirectional.only(start: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
                      child: Text('$unread',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  if (!pinned && unread == 0) const SizedBox(height: 18),
                ],
              ),
            ],
          ),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: doc.id))),
          onLongPress: () => _menu(doc),
        );

    if (isGroup) return row(_titleOf(d), d['groupPhoto'] as String?);
    final otherId = (d['participants'] as List)
        .firstWhere((id) => id != _uid, orElse: () => _uid) as String;
    return UserBuilder(
      uid: otherId,
      builder: (_, u) => row((u['name'] ?? _titleOf(d)).toString(), u['photo'] as String?),
    );
  }
}

class ArchivedScreen extends StatelessWidget {
  const ArchivedScreen({super.key});
  static final _q = ValueNotifier<String>('');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المحادثات المؤرشفة')),
      body: ChatsTab(query: _q, archived: true),
    );
  }
}
