import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'actions.dart';
import 'app_colors.dart';
import 'image_preview_screen.dart';
import 'contacts_service.dart';
import 'utils.dart';
import 'widgets.dart';

typedef StatusDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

int _ms(StatusDoc d) =>
    (d.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
    DateTime.now().millisecondsSinceEpoch;

bool _viewedByMe(StatusDoc d) =>
    List<String>.from(d.data()['viewers'] ?? const []).contains(currentUser.uid);

// ================== إنشاء حالة ==================

Future<void> postImageStatus(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('المعرض'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('الكاميرا'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ],
      ),
    ),
  );
  if (source == null) return;
  final x = await ImagePicker().pickImage(source: source, maxWidth: 1024, imageQuality: 60);
  if (x == null) return;
  final bytes = await x.readAsBytes();
  if (!context.mounted) return;
  if (bytes.length > 600 * 1024) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('الصورة كبيرة، اختر صورة أصغر')));
    return;
  }
  final caption = await Navigator.push<String>(
    context,
    MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImagePreviewScreen(bytes: bytes, chatTitle: 'حالتي')),
  );
  if (caption == null) return; // أُلغي النشر
  await _addStatus({'type': 'image', 'image': base64Encode(bytes), 'text': caption});
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('تم نشر الحالة')));
  }
}

void openTextStatusCreator(BuildContext context) {
  Navigator.push(
      context, MaterialPageRoute(builder: (_) => const CreateTextStatusScreen()));
}

Future<void> _addStatus(Map<String, dynamic> data) async {
  final now = DateTime.now();
  // تظهر الحالة لجهات اتصالك المسجلة في التطبيق فقط (مثل واتساب)، ولك أنت
  var visibleTo = <String>[currentUser.uid];
  var mode = 'all';
  var picked = <String>{};
  try {
    final me = await fs.collection('users').doc(currentUser.uid).get();
    final p = me.data()?['statusPrivacy'];
    if (p is Map) {
      mode = (p['mode'] ?? 'all').toString();
      picked = List<String>.from(p['list'] ?? const []).toSet();
    }
  } catch (_) {}
  try {
    final res = await ContactsService.load();
    final contacts = res.matches.map((m) => m.uid);
    if (mode == 'only') {
      visibleTo = {currentUser.uid, ...picked}.toList();
    } else if (mode == 'except') {
      visibleTo = {currentUser.uid, ...contacts.where((u) => !picked.contains(u))}.toList();
    } else {
      visibleTo = {currentUser.uid, ...contacts}.toList();
    }
  } catch (_) {
    if (mode == 'only') visibleTo = {currentUser.uid, ...picked}.toList();
  }
  await fs.collection('statuses').add({
    ...data,
    'uid': currentUser.uid,
    'name': currentUser.displayName ?? '',
    'createdAt': FieldValue.serverTimestamp(),
    'expiresAt': Timestamp.fromDate(now.add(const Duration(hours: 24))),
    'viewers': <String>[],
    'visibleTo': visibleTo,
  });
}

class CreateTextStatusScreen extends StatefulWidget {
  const CreateTextStatusScreen({super.key});

  @override
  State<CreateTextStatusScreen> createState() => _CreateTextStatusScreenState();
}

class _CreateTextStatusScreenState extends State<CreateTextStatusScreen> {
  final _ctrl = TextEditingController();
  int _color = 0;
  bool _sending = false;

  Future<void> _post() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    await _addStatus({
      'type': 'text',
      'text': text,
      'color': AppColors.statusColors[_color].value,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.statusColors[_color],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => setState(
                () => _color = (_color + 1) % AppColors.statusColors.length),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: null,
            maxLength: 300,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 28),
            cursorColor: Colors.white,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            decoration: const InputDecoration(
              hintText: 'اكتب حالة',
              hintStyle: TextStyle(color: Colors.white54),
              border: InputBorder.none,
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _sending ? null : _post,
        child: const Icon(Icons.send),
      ),
    );
  }
}

// ================== تبويب الحالة ==================

class StatusTab extends StatefulWidget {
  const StatusTab({super.key});

  @override
  State<StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<StatusTab> {
  // الحالات المسموح لي بمشاهدتها فقط (الانتهاء يُفلتر داخل التطبيق)
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = fs
      .collection('statuses')
      .where('visibleTo', arrayContains: currentUser.uid)
      .snapshots();

  @override
  void initState() {
    super.initState();
    _cleanupExpired();
  }

  /// حذف حالاتي المنتهية من قاعدة البيانات لتوفير المساحة
  Future<void> _cleanupExpired() async {
    try {
      final snap = await fs
          .collection('statuses')
          .where('visibleTo', arrayContains: currentUser.uid)
          .get();
      final now = DateTime.now();
      final batch = fs.batch();
      var n = 0;
      for (final d in snap.docs) {
        final data = d.data();
        final exp = (data['expiresAt'] as Timestamp?)?.toDate();
        if (data['uid'] == currentUser.uid && exp != null && exp.isBefore(now)) {
          batch.delete(d.reference);
          n++;
        }
      }
      if (n > 0) await batch.commit();
    } catch (_) {}
  }

  void _open(List<StatusDoc> list, String ownerUid) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => StatusViewerScreen(statuses: list, ownerUid: ownerUid)),
    );
  }

  Widget _ring({required Widget child, required bool unseen, required bool has}) {
    if (!has) return child;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: unseen ? AppColors.accent : Theme.of(context).disabledColor, width: 2.5),
      ),
      child: child,
    );
  }

  Future<void> _muteMenu(String ownerUid, bool muted) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: Icon(muted ? Icons.volume_up_outlined : Icons.volume_off_outlined),
          title: Text(muted ? 'إلغاء كتم الحالات' : 'كتم حالات هذا الشخص'),
          onTap: () {
            Navigator.pop(ctx);
            fs.collection('users').doc(currentUser.uid).update({
              'mutedStatus': muted
                  ? FieldValue.arrayRemove([ownerUid])
                  : FieldValue.arrayUnion([ownerUid])
            }).catchError((_) {});
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return UserBuilder(
      uid: currentUser.uid,
      builder: (context, meDoc) => _list(context, List<String>.from(meDoc['mutedStatus'] ?? const [])),
    );
  }

  Widget _list(BuildContext context, List<String> mutedUids) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final now = DateTime.now();
        final byUser = <String, List<StatusDoc>>{};
        for (final d in snap.data!.docs) {
          final exp = (d.data()['expiresAt'] as Timestamp).toDate();
          if (exp.isAfter(now)) {
            byUser.putIfAbsent(d.data()['uid'] as String, () => []).add(d);
          }
        }
        for (final l in byUser.values) {
          l.sort((a, b) => _ms(a).compareTo(_ms(b)));
        }
        final uid = currentUser.uid;
        final mine = byUser[uid] ?? [];
        final allOthers = byUser.entries.where((e) => e.key != uid).toList()
          ..sort((a, b) => _ms(b.value.last).compareTo(_ms(a.value.last)));
        final others = allOthers.where((e) => !mutedUids.contains(e.key)).toList();
        final mutedList = allOthers.where((e) => mutedUids.contains(e.key)).toList();
        final recent = others.where((e) => e.value.any((s) => !_viewedByMe(s))).toList();
        final seen = others.where((e) => e.value.every(_viewedByMe)).toList();

        Widget tile(String ownerUid, List<StatusDoc> list, {bool isMe = false}) {
          final unseen = list.any((s) => !_viewedByMe(s));
          return UserBuilder(
            uid: ownerUid,
            builder: (_, u) => ListTile(
              leading: _ring(
                has: list.isNotEmpty,
                unseen: isMe ? true : unseen,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Avatar(
                        photo: u['photo'] as String?,
                        name: (u['name'] ?? '?').toString(),
                        radius: 26),
                    if (isMe && list.isEmpty)
                      const Positioned(
                        bottom: -2,
                        right: -2,
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: AppColors.accent,
                          child: Icon(Icons.add, size: 14, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              title: Text(isMe ? 'حالتي' : (u['name'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(list.isEmpty
                  ? 'اضغط لإضافة تحديث للحالة'
                  : '${dayLabel(DateTime.fromMillisecondsSinceEpoch(_ms(list.last)))} ${hhmm(DateTime.fromMillisecondsSinceEpoch(_ms(list.last)))}'),
              onLongPress: isMe ? null : () => _muteMenu(ownerUid, mutedUids.contains(ownerUid)),
              onTap: () {
                if (list.isEmpty) {
                  openTextStatusCreator(context);
                } else {
                  _open(list, ownerUid);
                }
              },
            ),
          );
        }

        Widget header(String t) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(t,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold)),
            );

        return ListView(
          children: [
            tile(uid, mine, isMe: true),
            if (recent.isNotEmpty) header('التحديثات الأخيرة'),
            for (final e in recent) tile(e.key, e.value),
            if (seen.isNotEmpty) header('تمت المشاهدة'),
            for (final e in seen) tile(e.key, e.value),
            if (mutedList.isNotEmpty) header('الحالات المكتومة'),
            for (final e in mutedList) Opacity(opacity: 0.55, child: tile(e.key, e.value)),
            if (allOthers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('لا توجد تحديثات حالة من الآخرين الآن')),
              ),
          ],
        );
      },
    );
  }
}

// ================== عارض الحالة ==================

class StatusViewerScreen extends StatefulWidget {
  final List<StatusDoc> statuses;
  final String ownerUid;
  const StatusViewerScreen({super.key, required this.statuses, required this.ownerUid});

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(seconds: 5));
  late final List<StatusDoc> _items = [...widget.statuses];
  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();
  int _i = 0;

  bool get _isMine => widget.ownerUid == currentUser.uid;

  @override
  void initState() {
    super.initState();
    _anim.addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
    _replyFocus.addListener(() {
      if (_replyFocus.hasFocus) {
        _anim.stop();
      } else if (mounted) {
        _anim.forward();
      }
    });
    // ابدأ من أول حالة لم تُشاهد
    final firstUnseen = _items.indexWhere((s) => !_viewedByMe(s));
    if (!_isMine && firstUnseen > 0) _i = firstUnseen;
    _start();
  }

  void _start() {
    _anim.forward(from: 0);
    if (!_isMine) {
      _items[_i].reference.update({
        'viewers': FieldValue.arrayUnion([currentUser.uid])
      }).catchError((_) {});
    }
  }

  void _next() {
    if (_i < _items.length - 1) {
      setState(() => _i++);
      _start();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  void _prev() {
    if (_i > 0) {
      setState(() => _i--);
    }
    _start();
  }

  Future<void> _delete() async {
    _anim.stop();
    final doc = _items[_i];
    await doc.reference.delete();
    _items.removeAt(_i);
    if (_items.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() => _i = _i.clamp(0, _items.length - 1).toInt());
    _start();
  }

  void _showViewers() {
    _anim.stop();
    final viewers = List<String>.from(_items[_i].data()['viewers'] ?? const []);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('المشاهدات (${viewers.length})')),
            if (viewers.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('لا أحد شاهد بعد')),
            for (final v in viewers)
              UserBuilder(
                uid: v,
                builder: (_, u) => ListTile(
                  leading: Avatar(photo: u['photo'] as String?, name: (u['name'] ?? '?').toString()),
                  title: Text((u['name'] ?? '').toString()),
                ),
              ),
          ],
        ),
      ),
    ).then((_) {
      if (mounted) _anim.forward();
    });
  }

  /// الرد على الحالة برسالة تصل إلى محادثة صاحبها
  Future<void> _reply() async {
    final t = _replyCtrl.text.trim();
    if (t.isEmpty) return;
    _replyCtrl.clear();
    _replyFocus.unfocus();
    final me = currentUser.uid;
    final other = widget.ownerUid;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final chatId = chatIdFor(me, other);
      final u = await fs.collection('users').doc(other).get();
      await fs.collection('chats').doc(chatId).set({
        'participants': [me, other]..sort(),
        'isGroup': false,
        'names': {me: currentUser.displayName ?? '', other: (u.data()?['name'] ?? '').toString()},
      }, SetOptions(merge: true));
      final st = _items[_i].data();
      final quoted = (st['text'] ?? '').toString();
      await sendToChat(chatId, [me, other], {
        'type': 'text',
        'text': t,
        'replyText': quoted.isEmpty ? 'رد على حالتك' : 'رد على حالتك: $quoted',
      }, t);
      messenger.showSnackBar(const SnackBar(content: Text('تم إرسال الرد')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذر إرسال الرد')));
    }
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    _replyFocus.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _items[_i].data();
    final isText = s['type'] == 'text';
    final rtl = Directionality.of(context) == TextDirection.rtl;
    Uint8List? imgBytes;
    if (!isText) imgBytes = decodePhoto(s['image'] as String);

    return Scaffold(
      backgroundColor: isText ? Color(s['color'] as int) : Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (_) => _anim.stop(),
        onLongPressEnd: (_) => _anim.forward(),
        onTapUp: (d) {
          final left = d.globalPosition.dx < MediaQuery.of(context).size.width / 2;
          final goNext = rtl ? left : !left;
          goNext ? _next() : _prev();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (isText)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text((s['text'] ?? '').toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 30)),
                ),
              )
            else
              Center(child: Image.memory(imgBytes!, fit: BoxFit.contain)),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: AnimatedBuilder(
                      animation: _anim,
                      builder: (_, __) => Row(
                        children: [
                          for (var j = 0; j < _items.length; j++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: LinearProgressIndicator(
                                  value: j < _i ? 1 : (j == _i ? _anim.value : 0),
                                  minHeight: 3,
                                  backgroundColor: Colors.white30,
                                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  ListTile(
                    leading: UserAvatar(uid: widget.ownerUid, radius: 20),
                    title: UserBuilder(
                      uid: widget.ownerUid,
                      builder: (_, u) => Text(
                          _isMine ? 'حالتي' : (u['name'] ?? '').toString(),
                          style: const TextStyle(color: Colors.white)),
                    ),
                    subtitle: Text(
                      hhmm(DateTime.fromMillisecondsSinceEpoch(_ms(_items[_i]))),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
                  if (!isText && (s['text'] ?? '').toString().isNotEmpty)
                    Container(
                      width: double.infinity,
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text((s['text'] ?? '').toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  if (!_isMine)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: TextField(
                        controller: _replyCtrl,
                        focusNode: _replyFocus,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: Colors.white,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _reply(),
                        decoration: InputDecoration(
                          hintText: 'رد على الحالة...',
                          hintStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: Colors.black45,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: _reply,
                          ),
                        ),
                      ),
                    ),
                  if (_isMine)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: _showViewers,
                            icon: const Icon(Icons.visibility, color: Colors.white),
                            label: Text(
                              '${List.from(s['viewers'] ?? const []).length}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.white),
                            onPressed: _delete,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
