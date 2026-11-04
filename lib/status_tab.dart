import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_colors.dart';
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
  await _addStatus({'type': 'image', 'image': base64Encode(bytes)});
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('تم نشر الحالة')));
  }
}

void openTextStatusCreator(BuildContext context) {
  Navigator.push(
      context, MaterialPageRoute(builder: (_) => const CreateTextStatusScreen()));
}

Future<void> _addStatus(Map<String, dynamic> data) {
  final now = DateTime.now();
  return fs.collection('statuses').add({
    ...data,
    'uid': currentUser.uid,
    'name': currentUser.displayName ?? '',
    'createdAt': FieldValue.serverTimestamp(),
    'expiresAt': Timestamp.fromDate(now.add(const Duration(hours: 24))),
    'viewers': <String>[],
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
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = fs
      .collection('statuses')
      .where('expiresAt', isGreaterThan: Timestamp.now())
      .snapshots();

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

  @override
  Widget build(BuildContext context) {
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
        final others = byUser.entries.where((e) => e.key != uid).toList()
          ..sort((a, b) => _ms(b.value.last).compareTo(_ms(a.value.last)));
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
            if (others.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('ما فيه تحديثات حالة من الآخرين الآن')),
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
  int _i = 0;

  bool get _isMine => widget.ownerUid == currentUser.uid;

  @override
  void initState() {
    super.initState();
    _anim.addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
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

  @override
  void dispose() {
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
