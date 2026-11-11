import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'chat_actions.dart';
import 'chat_screen.dart';
import 'contacts_service.dart';
import 'utils.dart';
import 'widgets.dart';

class ChatsTab extends StatefulWidget {
  final ValueListenable<String> query;
  final bool archived;

  /// المحادثات المحددة (الضغط المطوّل). إن كانت null تظهر قائمة خيارات بدل التحديد.
  final ValueNotifier<Set<String>>? selection;
  const ChatsTab({super.key, required this.query, this.archived = false, this.selection});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = fs
      .collection('chats')
      .where('participants', arrayContains: currentUser.uid)
      .snapshots();

  String get _uid => currentUser.uid;

  bool get _selecting => widget.selection?.value.isNotEmpty ?? false;

  @override
  void initState() {
    super.initState();
    widget.selection?.addListener(_onSelection);
  }

  @override
  void dispose() {
    widget.selection?.removeListener(_onSelection);
    super.dispose();
  }

  void _onSelection() {
    if (mounted) setState(() {});
  }

  void _toggle(String id) {
    final s = {...widget.selection!.value};
    if (!s.remove(id)) s.add(id);
    widget.selection!.value = s;
  }

  /// المحادثة محذوفة عندي ولم تصل رسالة أحدث منذ الحذف
  bool _hidden(Map<String, dynamic> d) {
    final m = d['clearedAt'];
    if (m is! Map || !m.containsKey(_uid)) return false;
    final ts = m[_uid];
    if (ts is! Timestamp) return true;
    final last = (d['lastMessageAt'] as Timestamp?)?.millisecondsSinceEpoch;
    if (last == null) return false; // رسالة جديدة قيد الإرسال
    return last <= ts.millisecondsSinceEpoch;
  }

  bool _flag(Map<String, dynamic> d, String key) =>
      List<String>.from(d[key] ?? const []).contains(_uid);

  String _titleOf(Map<String, dynamic> d) {
    if (d['isSaved'] == true) return 'الرسائل المحفوظة';
    if (d['isGroup'] == true) return (d['groupName'] ?? 'مجموعة').toString();
    final names = Map<String, dynamic>.from(d['names'] ?? {});
    final otherId =
        (d['participants'] as List).firstWhere((id) => id != _uid, orElse: () => '');
    return (names[otherId] ?? 'مستخدم').toString();
  }

  int _millis(Map<String, dynamic> d) =>
      (d['lastMessageAt'] as Timestamp?)?.millisecondsSinceEpoch ??
      DateTime.now().millisecondsSinceEpoch;

  // ---------- المجلدات (محفوظة في ملفك الشخصي ولا يراها غيرك) ----------
  String _folder = 'all'; // all | unread | معرّف مجلد
  List<Map<String, dynamic>> _folders = [];

  List<Map<String, dynamic>> _readFolders(Map<String, dynamic> u) {
    final raw = u['folders'];
    if (raw is! List) return [];
    return [
      for (final f in raw)
        if (f is Map)
          {
            'id': (f['id'] ?? '').toString(),
            'name': (f['name'] ?? '').toString(),
            'chats': List<String>.from(f['chats'] ?? const []),
          }
    ];
  }

  Future<void> _saveFolders(List<Map<String, dynamic>> list) async {
    try {
      await fs.collection('users').doc(_uid).update({'folders': list});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر حفظ المجلد')));
      }
    }
  }

  Future<String?> _askName(String title, {String initial = ''}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
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
  }

  Future<void> _newFolder() async {
    final name = await _askName('مجلد جديد');
    if (name == null || name.isEmpty) return;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await _saveFolders([
      ..._folders,
      {'id': id, 'name': name, 'chats': <String>[]}
    ]);
    if (mounted) setState(() => _folder = id);
  }

  void _folderMenu(Map<String, dynamic> f) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تغيير اسم المجلد'),
              onTap: () async {
                Navigator.pop(ctx);
                final name = await _askName('اسم المجلد', initial: f['name'] as String);
                if (name == null || name.isEmpty) return;
                await _saveFolders([
                  for (final x in _folders) x['id'] == f['id'] ? {...x, 'name': name} : x
                ]);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text('حذف المجلد',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              subtitle: const Text('المحادثات نفسها لا تُحذف'),
              onTap: () async {
                Navigator.pop(ctx);
                await _saveFolders([
                  for (final x in _folders)
                    if (x['id'] != f['id']) x
                ]);
                if (mounted && _folder == f['id']) setState(() => _folder = 'all');
              },
            ),
          ],
        ),
      ),
    );
  }

  /// اختيار المجلدات التي تضم هذه المحادثة
  Future<void> _chooseFolders(String chatId) async {
    if (_folders.isEmpty) {
      await _newFolder();
      return;
    }
    final inFolder = {
      for (final f in _folders) f['id'] as String: (f['chats'] as List<String>).contains(chatId)
    };
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('إضافة إلى مجلد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final f in _folders)
                  CheckboxListTile(
                    value: inFolder[f['id']] ?? false,
                    title: Text(f['name'] as String),
                    onChanged: (v) => setS(() => inFolder[f['id'] as String] = v ?? false),
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
    if (ok != true) return;
    await _saveFolders([
      for (final f in _folders)
        {
          ...f,
          'chats': [
            ...(f['chats'] as List<String>).where((c) => c != chatId),
            if (inFolder[f['id']] ?? false) chatId,
          ],
        }
    ]);
  }

  Widget _chips() {
    Widget chip(String id, String label, {Map<String, dynamic>? folder}) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: GestureDetector(
            onLongPress: folder == null ? null : () => _folderMenu(folder),
            child: ChoiceChip(
              label: Text(label),
              selected: _folder == id,
              onSelected: (_) => setState(() => _folder = id),
            ),
          ),
        );
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          chip('all', 'الكل'),
          chip('unread', 'غير المقروءة'),
          for (final f in _folders) chip(f['id'] as String, f['name'] as String, folder: f),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('مجلد'),
            onPressed: _newFolder,
          ),
        ],
      ),
    );
  }

  /// الرسائل المحفوظة: محادثة مع نفسك
  Widget _savedRow(Map<String, dynamic>? saved) {
    final last = (saved?['lastMessage'] ?? '').toString();
    return ListTile(
      leading: const CircleAvatar(
        radius: 28,
        backgroundColor: AppColors.accent,
        child: Icon(Icons.bookmark, color: Colors.white),
      ),
      title: const Text('الرسائل المحفوظة', style: TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(last.isEmpty ? 'احفظ ملاحظاتك وصورك هنا' : last,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () async {
        final id = 'saved_$_uid';
        try {
          await fs.collection('chats').doc(id).set({
            'participants': [_uid],
            'isGroup': false,
            'isSaved': true,
            'names': {_uid: 'الرسائل المحفوظة'},
          }, SetOptions(merge: true));
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('تعذر فتح الرسائل المحفوظة')));
          }
          return;
        }
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: id)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: widget.query,
      builder: (context, q, _) => UserBuilder(
        uid: _uid,
        builder: (context, me) {
          _folders = _readFolders(me);
          if (_folder != 'all' &&
              _folder != 'unread' &&
              !_folders.any((f) => f['id'] == _folder)) {
            _folder = 'all';
          }
          return _body(context, q);
        },
      ),
    );
  }

  Widget _body(BuildContext context, String q) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('تعذر تحميل المحادثات'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          Map<String, dynamic>? saved;
          for (final d in snap.data!.docs) {
            if (d.data()['isSaved'] == true) saved = d.data();
          }
          final all = snap.data!.docs
              .where((d) =>
                  d.data()['isSaved'] != true &&
                  d.data()['lastMessage'] != null &&
                  !_hidden(d.data()))
              .toList();
          final archivedCount = all.where((d) => _flag(d.data(), 'archivedBy')).length;
          final folderChats = _folders
              .where((f) => f['id'] == _folder)
              .expand((f) => f['chats'] as List<String>)
              .toSet();
          final docs = all
              .where((d) => _flag(d.data(), 'archivedBy') == widget.archived)
              .where((d) => q.isEmpty || _titleOf(d.data()).contains(q))
              .where((d) {
                if (widget.archived || _folder == 'all') return true;
                if (_folder == 'unread') {
                  return ((d.data()['unread'] as Map?)?[_uid] ?? 0) > 0;
                }
                return folderChats.contains(d.id);
              })
              .toList()
            ..sort((a, b) {
              final pa = _flag(a.data(), 'pinnedBy') ? 1 : 0;
              final pb = _flag(b.data(), 'pinnedBy') ? 1 : 0;
              if (pa != pb) return pb.compareTo(pa);
              return _millis(b.data()).compareTo(_millis(a.data()));
            });

          final showHeader = !widget.archived && q.isEmpty;
          final showArchiveRow =
              !widget.archived && archivedCount > 0 && q.isEmpty && _folder == 'all';
          final headers = <Widget>[
            if (showHeader) _chips(),
            if (showHeader && _folder == 'all') _savedRow(saved),
            if (showArchiveRow)
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('المؤرشفة'),
                trailing: Text('$archivedCount'),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ArchivedScreen())),
              ),
          ];

          Widget? empty;
          if (docs.isEmpty) {
            final firstTime = _folder == 'all' && !widget.archived && q.isEmpty;
            empty = Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (firstTime || (!showHeader && q.isEmpty))
                    Opacity(
                      opacity: 0.9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset('assets/icon/icon.png', width: 96, height: 96),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    q.isNotEmpty
                        ? 'لا نتائج'
                        : (widget.archived
                            ? 'لا توجد محادثات مؤرشفة'
                            : (_folder == 'all'
                                ? 'ما عندك محادثات بعد.\nاضغط على زر المحادثة لبدء أول محادثة.'
                                : (_folder == 'unread'
                                    ? 'لا رسائل غير مقروءة'
                                    : 'المجلد فارغ.\nاضغط مطوّلاً على محادثة ثم "إضافة إلى مجلد".'))),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            );
          }
          final extra = empty == null ? 0 : 1;
          return ListView.builder(
            itemCount: headers.length + docs.length + extra,
            itemBuilder: (context, i) {
              if (i < headers.length) return headers[i];
              final j = i - headers.length;
              if (j < docs.length) return _tile(context, docs[j]);
              return empty!;
            },
          );
        },
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
              leading: const Icon(Icons.folder_outlined),
              title: const Text('إضافة إلى مجلد'),
              onTap: () {
                Navigator.pop(ctx);
                _chooseFolders(doc.id);
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
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text('حذف المحادثة',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                deleteChatsConfirm(context, {doc.id});
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

    final selected = widget.selection?.value.contains(doc.id) ?? false;

    Widget row(String title, String? photo) => ListTile(
          selected: selected,
          selectedTileColor: AppColors.primary.withAlpha(35),
          leading: Stack(
            children: [
              Avatar(photo: photo, name: title, isGroup: isGroup, radius: 28),
              if (selected)
                const Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    radius: 11,
                    backgroundColor: AppColors.primary,
                    child: Icon(Icons.check, size: 15, color: Colors.white),
                  ),
                ),
            ],
          ),
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
                  if (_flag(d, 'mutedBy'))
                    Icon(Icons.notifications_off, size: 16, color: Theme.of(context).hintColor),
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
          onTap: () {
            if (_selecting) {
              _toggle(doc.id);
            } else {
              Navigator.push(
                  context,
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 220),
                    pageBuilder: (_, __, ___) => ChatScreen(chatId: doc.id),
                    transitionsBuilder: (_, anim, __, child) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0.06, 0), end: Offset.zero)
                            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                        child: child,
                      ),
                    ),
                  ));
            }
          },
          onLongPress: () => widget.selection != null ? _toggle(doc.id) : _menu(doc),
        );

    if (isGroup) return row(_titleOf(d), d['groupPhoto'] as String?);
    final otherId = (d['participants'] as List)
        .firstWhere((id) => id != _uid, orElse: () => _uid) as String;
    return UserBuilder(
      uid: otherId,
      builder: (_, u) => ValueListenableBuilder<Map<String, String>?>(
        valueListenable: ContactsService.names,
        builder: (_, names, __) {
          final shown = displayNameOf(otherId, u, names);
          return row(shown.isNotEmpty ? shown : _titleOf(d), u['photo'] as String?);
        },
      ),
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
