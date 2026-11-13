import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'actions.dart';
import 'chat_actions.dart';
import 'contacts_service.dart';
import 'app_colors.dart';
import 'audio_bubble.dart';
import 'chat_wallpaper.dart';
import 'add_contact_screen.dart';
import 'forward_screen.dart';
import 'image_preview_screen.dart';
import 'image_viewer.dart';
import 'info_screen.dart';
import 'utils.dart';
import 'widgets.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  const ChatScreen({super.key, required this.chatId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _maxMediaBytes = 600 * 1024; // حد مستند Firestore ~1MB

  final _ctrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _recorder = AudioRecorder();
  late final _chatRef = fs.collection('chats').doc(widget.chatId);
  late final _msgsRef = _chatRef.collection('messages');
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _chatStream =
      _chatRef.snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _msgStream =
      _msgsRef.orderBy('createdAt', descending: true).limit(100).snapshots();

  Map<String, dynamic> _chat = {};
  final _scroll = ScrollController();
  final _showDown = ValueNotifier<bool>(false);
  String? _replyText;
  String? _editingId;
  bool _sendingMedia = false;
  bool _hasText = false;
  bool _typing = false;
  Timer? _typingTimer;
  bool _searching = false;
  bool _onlyStarred = false;
  String _q = '';
  bool _recording = false;
  int _recSecs = 0;
  Timer? _recTimer;

  String get _uid => currentUser.uid;
  bool get _isGroup => _chat['isGroup'] == true;
  List<String> get _participants =>
      List<String>.from(_chat['participants'] ?? const []);
  List<String> get _others => _participants.where((p) => p != _uid).toList();

  @override
  void initState() {
    super.initState();
    _chatRef.update({'unread.$_uid': 0}).catchError((_) {});
    _scroll.addListener(() {
      final far = _scroll.hasClients && _scroll.offset > 400;
      if (far != _showDown.value) _showDown.value = far;
    });
    _ctrl.addListener(() {
      final h = _ctrl.text.trim().isNotEmpty;
      if (h != _hasText) setState(() => _hasText = h);
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _recTimer?.cancel();
    _stopTyping();
    _recorder.dispose();
    _ctrl.dispose();
    _searchCtrl.dispose();
    _scroll.dispose();
    _showDown.dispose();
    super.dispose();
  }

  // ---------- الكتابة ----------
  void _onChanged(String t) {
    if (t.isNotEmpty && !_typing) {
      _typing = true;
      _chatRef.update({'typing.$_uid': true}).catchError((_) {});
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    if (!_typing) return;
    _typing = false;
    _chatRef.update({'typing.$_uid': false}).catchError((_) {});
  }

  // ---------- الإرسال ----------
  Future<void> _addMessage(Map<String, dynamic> data, String preview) async {
    final reply = _replyText;
    setState(() => _replyText = null);
    await sendToChat(widget.chatId, _participants, {...data, 'replyText': reply}, preview);
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    _typingTimer?.cancel();
    _stopTyping();

    if (_editingId != null) {
      final id = _editingId!;
      setState(() => _editingId = null);
      await _msgsRef.doc(id).update({'text': text, 'edited': true});
      return;
    }
    await _addMessage({'type': 'text', 'text': text}, text);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final x = await ImagePicker()
          .pickImage(source: source, maxWidth: 1024, imageQuality: 60);
      if (x == null) return;
      await _sendImageBytes(await x.readAsBytes());
    } catch (_) {
      _snack('تعذر إرسال الصورة');
    }
  }

  Future<void> _sendImageBytes(Uint8List bytes) async {
    try {
      if (bytes.length > _maxMediaBytes) {
        _snack('الصورة كبيرة، اختر صورة أصغر');
        return;
      }
      if (!mounted) return;
      final names = Map<String, dynamic>.from(_chat['names'] ?? {});
      final other = _others.isEmpty ? '' : (names[_others.first] ?? '').toString();
      final caption = await Navigator.push<String>(
        context,
        MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => ImagePreviewScreen(
                bytes: bytes, chatTitle: _isGroup ? (_chat['name'] ?? '').toString() : other)),
      );
      if (caption == null) return; // أُلغيت المعاينة
      setState(() => _sendingMedia = true);
      await _addMessage(
          {'type': 'image', 'image': base64Encode(bytes), 'text': caption},
          caption.isEmpty ? '📷 صورة' : '📷 $caption');
    } catch (_) {
      _snack('تعذر إرسال الصورة');
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  // ---------- الرسائل الصوتية ----------
  Future<void> _startRec() async {
    try {
      if (!await _recorder.hasPermission()) {
        _snack('اسمح للتطبيق باستخدام المايكروفون من إعدادات الجوال');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 16000, numChannels: 1),
        path: path,
      );
      setState(() {
        _recording = true;
        _recSecs = 0;
      });
      _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recSecs++);
        if (_recSecs >= 90) _finishRec(send: true);
      });
    } catch (_) {
      _snack('تعذر بدء التسجيل');
    }
  }

  Future<void> _finishRec({required bool send}) async {
    _recTimer?.cancel();
    final secs = _recSecs;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
    if (path == null) return;
    final file = File(path);
    try {
      if (!send || secs < 1) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxMediaBytes) {
        _snack('التسجيل طويل، حاول تسجيلاً أقصر');
        return;
      }
      setState(() => _sendingMedia = true);
      await _addMessage({
        'type': 'audio',
        'audio': base64Encode(bytes),
        'duration': secs,
        'text': '',
      }, '🎤 رسالة صوتية');
    } catch (_) {
      _snack('تعذر إرسال التسجيل');
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- القراءة ----------
  void _markRead(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final unread = docs.where((d) {
      final data = d.data();
      if (data['senderId'] == _uid) return false;
      return !List<String>.from(data['readBy'] ?? const []).contains(_uid);
    }).toList();
    if (unread.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final batch = fs.batch();
      for (final d in unread) {
        batch.update(d.reference, {
          'readBy': FieldValue.arrayUnion([_uid])
        });
      }
      batch.update(_chatRef, {'unread.$_uid': 0});
      batch.commit().catchError((_) {});
    });
  }

  // ---------- خيارات الرسالة ----------
  void _react(QueryDocumentSnapshot<Map<String, dynamic>> doc, String emoji) {
    final current = Map<String, dynamic>.from(doc.data()['reactions'] ?? {});
    doc.reference.update({
      'reactions.$_uid': current[_uid] == emoji ? FieldValue.delete() : emoji,
    });
  }

  void _messageInfo(Map<String, dynamic> data) {
    final ts = (data['createdAt'] as Timestamp?)?.toDate();
    final readBy = List<String>.from(data['readBy'] ?? const []);
    final names = Map<String, dynamic>.from(_chat['names'] ?? {});
    final readers = _others.where(readBy.contains).toList();
    final waiting = _others.where((u) => !readBy.contains(u)).toList();
    String n(String u) => (names[u] ?? 'مستخدم').toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('معلومات الرسالة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('أُرسلت: ${ts == null ? '...' : '${dayLabel(ts)} ${hhmm(ts)}'}'),
            const SizedBox(height: 10),
            if (readers.isNotEmpty) Text('قرأها: ${readers.map(n).join('، ')}'),
            if (waiting.isNotEmpty) Text('لم يقرأها بعد: ${waiting.map(n).join('، ')}'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
      ),
    );
  }

  void _options(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final mine = data['senderId'] == _uid;
    final type = (data['type'] ?? 'text') as String;
    final text = (data['text'] ?? '') as String;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final e in const ['👍', '❤️', '😂', '😮', '😢', '🙏'])
                      InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _react(doc, e);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(e, style: const TextStyle(fontSize: 26)),
                        ),
                      ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('رد'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _replyText = previewOf(data);
                    _editingId = null;
                  });
                },
              ),
              if (type == 'image') ...[
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('حفظ في المعرض'),
                  onTap: () {
                    Navigator.pop(ctx);
                    saveImageToGallery(context, base64Decode(data['image'] as String));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('مشاركة'),
                  onTap: () {
                    Navigator.pop(ctx);
                    shareImage(context, base64Decode(data['image'] as String));
                  },
                ),
              ],
              ListTile(
                leading: Icon(List<String>.from(data['starredBy'] ?? const []).contains(_uid)
                    ? Icons.star_border
                    : Icons.star),
                title: Text(List<String>.from(data['starredBy'] ?? const []).contains(_uid)
                    ? 'إلغاء التمييز'
                    : 'تمييز بنجمة'),
                onTap: () {
                  Navigator.pop(ctx);
                  final on = List<String>.from(data['starredBy'] ?? const []).contains(_uid);
                  doc.reference.update({
                    'starredBy': on ? FieldValue.arrayRemove([_uid]) : FieldValue.arrayUnion([_uid]),
                  });
                },
              ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('معلومات الرسالة'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _messageInfo(data);
                  },
                ),
              if (type == 'text')
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('نسخ'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: text));
                  },
                ),
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('تحويل'),
                onTap: () {
                  Navigator.pop(ctx);
                  final msg = <String, dynamic>{
                    'type': type,
                    'text': text,
                    if (type == 'image') 'image': data['image'],
                    if (type == 'audio') 'audio': data['audio'],
                    if (type == 'audio') 'duration': data['duration'],
                  };
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ForwardScreen(message: msg)));
                },
              ),
              if (mine && type == 'text')
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('تعديل'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _editingId = doc.id;
                      _replyText = null;
                      _ctrl.text = text;
                    });
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('حذف عندي'),
                onTap: () {
                  Navigator.pop(ctx);
                  deleteMessageForMe(doc.reference, _participants);
                },
              ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined),
                  title: const Text('حذف للجميع'),
                  onTap: () {
                    Navigator.pop(ctx);
                    doc.reference.delete();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openInfo() {
    if (_chat['isSaved'] == true) return;
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => ChatInfoScreen(chatId: widget.chatId)));
  }

  // ---------- الواجهة ----------
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _chatStream,
      builder: (context, snap) {
        final data = snap.data?.data();
        if (data != null) _chat = data;
        if (_chat.isEmpty) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          appBar: _appBar(context),
          body: ChatWallpaper(
            dark: dark,
            child: Column(
              children: [
                _unsavedBanner(context),
                Expanded(child: _messages(context)),
                _replyBar(context),
                _inputBar(context),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _typingLabel() {
    final typing = Map<String, dynamic>.from(_chat['typing'] ?? {});
    final names = Map<String, dynamic>.from(_chat['names'] ?? {});
    final who = typing.entries
        .where((e) => e.value == true && e.key != _uid)
        .map((e) => (names[e.key] ?? '').toString())
        .toList();
    if (who.isEmpty) return null;
    return _isGroup ? '${who.first} يكتب...' : 'يكتب...';
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    if (_searching) {
      return AppBar(
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: const InputDecoration(
              hintText: 'بحث في المحادثة',
              hintStyle: TextStyle(color: Colors.white70),
              border: InputBorder.none),
          onChanged: (v) => setState(() => _q = v.trim()),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _searching = false;
              _q = '';
              _searchCtrl.clear();
            }),
          ),
        ],
      );
    }

    Widget header(String title, String? photo, String subtitle) => InkWell(
          onTap: _openInfo,
          child: Row(
            children: [
              Avatar(photo: photo, name: title, isGroup: _isGroup, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        );

    final typing = _typingLabel();
    Widget title;
    String callTitle;
    if (_isGroup) {
      callTitle = (_chat['groupName'] ?? 'مجموعة').toString();
      final names = Map<String, dynamic>.from(_chat['names'] ?? {});
      final members = _participants.map((p) => (names[p] ?? '').toString()).join('، ');
      title = header(callTitle, _chat['groupPhoto'] as String?, typing ?? members);
    } else if (_chat['isSaved'] == true) {
      callTitle = 'الرسائل المحفوظة';
      title = header('الرسائل المحفوظة', null, 'ملاحظات لك وحدك');
    } else {
      final otherId = _others.isEmpty ? _uid : _others.first;
      final names = Map<String, dynamic>.from(_chat['names'] ?? {});
      callTitle = (names[otherId] ?? 'مستخدم').toString();
      title = UserBuilder(
        uid: otherId,
        builder: (_, u) {
          final shown = displayNameOf(otherId, u, ContactsService.names.value);
          return header(shown.isNotEmpty ? shown : callTitle, u['photo'] as String?,
              typing ?? presenceText(u));
        },
      );
    }

    return AppBar(
      titleSpacing: 0,
      title: title,
      actions: [
        if (_chat['isSaved'] != true) ...[
        IconButton(
          icon: const Icon(Icons.videocam),
          onPressed: () =>
              startCall(context, calleeIds: _others, title: callTitle, video: true),
        ),
        IconButton(
          icon: const Icon(Icons.call),
          onPressed: () =>
              startCall(context, calleeIds: _others, title: callTitle, video: false),
        ),
        ],
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'search') {
              setState(() => _searching = true);
            } else if (v == 'starred') {
              setState(() => _onlyStarred = !_onlyStarred);
            } else if (v == 'mute') {
              toggleChatFlag({widget.chatId}, 'mutedBy');
            } else if (v == 'delete') {
              deleteChatsConfirm(context, {widget.chatId}).then((done) {
                if (done && mounted) Navigator.pop(context);
              });
            } else {
              _openInfo();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'search', child: Text('بحث')),
            PopupMenuItem(
                value: 'starred',
                child: Text(_onlyStarred ? 'عرض كل الرسائل' : 'الرسائل المميّزة ⭐')),
            PopupMenuItem(
                value: 'mute',
                child: Text(List<String>.from(_chat['mutedBy'] ?? const []).contains(_uid)
                    ? 'إلغاء كتم الإشعارات'
                    : 'كتم الإشعارات')),
            const PopupMenuItem(value: 'info', child: Text('معلومات')),
            const PopupMenuItem(value: 'delete', child: Text('حذف المحادثة')),
          ],
        ),
      ],
    );
  }

  Widget _messages(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _msgStream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        _markRead(snap.data!.docs);
        final cleared = ((_chat['clearedAt'] as Map?)?[_uid] as Timestamp?)?.toDate();
        var docs = snap.data!.docs
            .where((d) =>
                !List<String>.from(d.data()['deletedFor'] ?? const []).contains(_uid))
            .where((d) {
              if (cleared == null) return true;
              final t = (d.data()['createdAt'] as Timestamp?)?.toDate();
              return t == null || t.isAfter(cleared);
            })
            .toList();
        if (_onlyStarred) {
          docs = docs
              .where((d) => List<String>.from(d.data()['starredBy'] ?? const []).contains(_uid))
              .toList();
        }
        if (_searching && _q.isNotEmpty) {
          docs = docs.where((d) => (d.data()['text'] ?? '').toString().contains(_q)).toList();
        }
        DateTime dt(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            (d.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        if (docs.isEmpty) {
          return Center(child: Text(_onlyStarred ? 'لا رسائل مميّزة' : (_searching ? 'لا نتائج' : 'ابدأ المحادثة 👋')));
        }
        final list = ListView.builder(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final showDay = i == docs.length - 1 || !sameDay(dt(docs[i]), dt(docs[i + 1]));
            final older = i + 1 < docs.length ? docs[i + 1] : null;
            final tail = older == null ||
                older.data()['senderId'] != docs[i].data()['senderId'] ||
                !sameDay(dt(docs[i]), dt(older));
            return Column(
              children: [
                if (showDay) _dayChip(context, dayLabel(dt(docs[i]))),
                _swipeToReply(context, docs[i], _bubble(context, docs[i], tail: tail)),
              ],
            );
          },
        );
        return Stack(children: [
          list,
          Positioned.directional(
            textDirection: Directionality.of(context),
            end: 14,
            bottom: 10,
            child: ValueListenableBuilder<bool>(
              valueListenable: _showDown,
              builder: (_, show, __) => AnimatedScale(
                scale: show ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: FloatingActionButton.small(
                  heroTag: null,
                  elevation: 2,
                  backgroundColor: dark ? const Color(0xFF262B36) : Colors.white,
                  foregroundColor: dark ? Colors.white70 : const Color(0xFF54656F),
                  onPressed: () => _scroll.animateTo(0,
                      duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }

  /// اسحب الرسالة جانباً للرد عليها
  Widget _swipeToReply(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> d, Widget child) {
    final icon = Container(
      alignment: AlignmentDirectional.center,
      width: 56,
      child: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.black12,
        child: Icon(Icons.reply, size: 18, color: Theme.of(context).hintColor),
      ),
    );
    return Dismissible(
      key: ValueKey('sw_${d.id}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {DismissDirection.startToEnd: 0.18, DismissDirection.endToStart: 0.18},
      background: Align(alignment: AlignmentDirectional.centerStart, child: icon),
      secondaryBackground: Align(alignment: AlignmentDirectional.centerEnd, child: icon),
      confirmDismiss: (_) async {
        HapticFeedback.selectionClick();
        setState(() {
          _replyText = previewOf(d.data());
          _editingId = null;
        });
        return false;
      },
      child: child,
    );
  }

  Widget _dayChip(BuildContext context, String label) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF182229) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))],
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12.5, color: dark ? const Color(0xFF8696A0) : const Color(0xFF54656F))),
    );
  }

  Color _nameColor(String uid) {
    const colors = [
      Color(0xFFE65100), Color(0xFF6A1B9A), Color(0xFF00838F),
      Color(0xFFC62828), Color(0xFF2E7D32), Color(0xFF1565C0),
    ];
    return colors[uid.hashCode.abs() % colors.length];
  }

  Widget _bubble(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> d,
      {bool tail = true}) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final data = d.data();
    final senderId = data['senderId'] as String?;
    final mine = senderId == _uid;
    final ts = data['createdAt'] as Timestamp?;
    final reply = data['replyText'] as String?;
    final type = (data['type'] ?? 'text') as String;
    final isImage = type == 'image';
    final isAudio = type == 'audio';
    final isSticker = type == 'sticker';
    final readBy = List<String>.from(data['readBy'] ?? const []);
    final readAll = _others.isNotEmpty && _others.every(readBy.contains);
    final time = ts == null ? '' : hhmm(ts.toDate());
    final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
    final edited = data['edited'] == true;
    final metaColor = dark ? const Color(0xFF8696A0) : const Color(0xFF667781);

    // الوقت وعلامات القراءة داخل الفقاعة مثل واتساب
    Widget meta({Color? color}) {
      final c = color ?? metaColor;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (List<String>.from(data['starredBy'] ?? const []).contains(_uid))
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 3),
              child: Icon(Icons.star, size: 12, color: c),
            ),
          if (edited) Text('معدّلة ', style: TextStyle(fontSize: 11, color: c)),
          Text(time, style: TextStyle(fontSize: 11, color: c)),
          if (mine) ...[
            const SizedBox(width: 3),
            Icon(
              ts == null ? Icons.access_time : (readAll ? Icons.done_all : Icons.done),
              size: 16,
              color: readAll ? const Color(0xFF53BDEB) : c,
            ),
          ],
        ],
      );
    }

    Widget body;
    if (isImage && (data['text'] ?? '').toString().isNotEmpty) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Base64Image(data['image'] as String),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(6, 5, 6, 1),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text(data['text'].toString(), style: const TextStyle(fontSize: 16, height: 1.3)),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 10, top: 4),
                  child: meta(),
                ),
              ],
            ),
          ),
        ],
      );
    } else if (isImage) {
      body = Stack(
        children: [
          _Base64Image(data['image'] as String),
          Positioned.directional(
            textDirection: Directionality.of(context),
            end: 6,
            bottom: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.black45, borderRadius: BorderRadius.circular(10)),
              child: meta(color: Colors.white),
            ),
          ),
        ],
      );
    } else if (isSticker) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(data['text'] ?? '', style: const TextStyle(fontSize: 72, height: 1.15)),
          if ((data['caption'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(data['caption'].toString(),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          meta(),
        ],
      );
    } else if (isAudio) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AudioBubble(data: data['audio'] as String, seconds: (data['duration'] ?? 0) as int),
          meta(),
        ],
      );
    } else {
      // الوقت وعلامات القراءة في سطر مستقل أسفل النص
      body = IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(data['text'] ?? '', style: const TextStyle(fontSize: 16, height: 1.3)),
            const SizedBox(height: 3),
            Align(alignment: AlignmentDirectional.centerEnd, child: meta()),
          ],
        ),
      );
    }

    // شكل HaiChat: زوايا مستديرة كبيرة وزاوية سفلية صغيرة تدل على المرسل
    const r = Radius.circular(20);
    const small = Radius.circular(6);
    final shape = BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: (tail && mine) ? small : r,
      bottomRight: (tail && !mine) ? small : r,
    );
    final rtl = Directionality.of(context) == TextDirection.rtl;

    final bubble = GestureDetector(
      onLongPress: () => _options(d),
      child: Container(
        margin: EdgeInsets.only(top: tail ? 6 : 1.5, bottom: 1.5),
        padding: isImage
            ? const EdgeInsets.all(3)
            : const EdgeInsetsDirectional.fromSTEB(12, 7, 12, 5),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8, minWidth: isAudio ? 240 : 0),
        decoration: BoxDecoration(
          color: isSticker
              ? Colors.transparent
              : mine
                  ? (dark ? null : AppColors.mineLight)
                  : (dark ? AppColors.otherDark : AppColors.otherLight),
          gradient: (mine && dark && !isSticker)
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF9A1B4A), Color(0xFF6B0F36)])
              : null,
          border: (!mine && !isSticker)
              ? Border.all(color: dark ? const Color(0xFF4A2B3B) : const Color(0xFFDCCBD3), width: 1)
              : null,
          borderRadius: shape,
          boxShadow: (dark || isSticker)
              ? null
              : const [BoxShadow(color: Colors.black12, blurRadius: 0.5, offset: Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (data['forwarded'] == true)
              Padding(
                padding: EdgeInsets.only(bottom: 3, left: isImage ? 6 : 0, right: isImage ? 6 : 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.forward, size: 14, color: metaColor),
                    const SizedBox(width: 4),
                    Text('محوّلة',
                        style: TextStyle(
                            fontSize: 12, fontStyle: FontStyle.italic, color: metaColor)),
                  ],
                ),
              ),
            if (_isGroup && !mine && senderId != null && tail)
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(isImage ? 6 : 0, isImage ? 2 : 0, 0, 2),
                child: Text((data['senderName'] ?? '').toString(),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _nameColor(senderId))),
              ),
            if (reply != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsetsDirectional.fromSTEB(8, 5, 8, 5),
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                          start: BorderSide(color: scheme.primary, width: 4)),
                      color: dark ? Colors.black26 : Colors.black.withAlpha(15),
                    ),
                    child: Text(reply,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: metaColor)),
                  ),
                ),
              ),
            body,
          ],
        ),
      ),
    );

    return Align(
      alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: (mine == rtl) ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          bubble,
          if (reactions.isNotEmpty)
            Transform.translate(
              offset: const Offset(0, -8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF262B36) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 1, offset: Offset(0, 1))
                  ],
                ),
                child: Text(
                  '${reactions.values.toSet().join(' ')}${reactions.length > 1 ? ' ${reactions.length}' : ''}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _replyBar(BuildContext context) {
    if (_replyText == null && _editingId == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? const Color(0xFF1F2430) : const Color(0xFFF0F2F5),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 6),
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF16222A) : Colors.white,
                  border: BorderDirectional(
                      start: BorderSide(color: Theme.of(context).colorScheme.primary, width: 4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_editingId != null ? 'تعديل الرسالة' : 'رد',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary)),
                    if (_editingId == null)
                      Text(_replyText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() {
              if (_editingId != null) _ctrl.clear();
              _replyText = null;
              _editingId = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _banner(String text, {String? action, VoidCallback? onTap}) {
    return SafeArea(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(text),
            if (action != null) TextButton(onPressed: onTap, child: Text(action)),
          ],
        ),
      ),
    );
  }

  /// شريط "ليس في جهات اتصالك" لمحادثة فردية مع رقم غير محفوظ (مثل واتساب)
  Widget _unsavedBanner(BuildContext context) {
    if (_isGroup || _others.isEmpty) return const SizedBox.shrink();
    final other = _others.first;
    return ValueListenableBuilder<Map<String, String>?>(
      valueListenable: ContactsService.names,
      builder: (_, names, __) {
        // names == null: لم تُمنح صلاحية الجهات، فلا نزعج المستخدم
        if (names == null || (names[other] ?? '').isNotEmpty) return const SizedBox.shrink();
        return UserBuilder(
          uid: other,
          builder: (ctx, u) {
            final phone = (u['phone'] ?? '').toString();
            if (phone.isEmpty) return const SizedBox.shrink();
            final dark = Theme.of(ctx).brightness == Brightness.dark;
            return Material(
              color: dark ? const Color(0xFF1F2430) : Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(children: [
                  const Icon(Icons.person_add_alt_1, size: 20, color: AppColors.accent),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('هذا الرقم ليس في جهات اتصالك',
                        style: TextStyle(fontSize: 14)),
                  ),
                  TextButton(
                    onPressed: () async {
                      await Navigator.push(
                          ctx,
                          MaterialPageRoute(
                              builder: (_) => AddContactScreen(
                                  initialPhone: phone,
                                  initialName: (u['name'] ?? '').toString())));
                    },
                    child: const Text('إضافة'),
                  ),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  Widget _inputBar(BuildContext context) {
    if (_recording) return _recordingBar(context);
    if (_isGroup || _others.isEmpty) return _composer(context);
    final other = _others.first;
    return UserBuilder(
      uid: _uid,
      builder: (_, me) {
        final iBlocked = List<String>.from(me['blocked'] ?? const []).contains(other);
        return UserBuilder(
          uid: other,
          builder: (_, o) {
            final blockedMe = List<String>.from(o['blocked'] ?? const []).contains(_uid);
            if (iBlocked) {
              return _banner('حظرت هذا المستخدم',
                  action: 'إلغاء الحظر',
                  onTap: () => fs.collection('users').doc(_uid).update({
                        'blocked': FieldValue.arrayRemove([other])
                      }));
            }
            if (blockedMe) return _banner('لا يمكنك مراسلة هذا المستخدم');
            return _composer(context);
          },
        );
      },
    );
  }

  Widget _recordingBar(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              onPressed: () => _finishRec(send: false),
            ),
            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
            const SizedBox(width: 6),
            Text(mmss(_recSecs), style: const TextStyle(fontSize: 16)),
            const Expanded(child: SizedBox()),
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.accent,
              child: IconButton(
                color: Colors.white,
                icon: const Icon(Icons.send),
                onPressed: () => _finishRec(send: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _emojiSheet() {
    const emojis = [
      // وجوه
      '😀','😃','😄','😁','😆','😅','😂','🤣','😊','😇','🙂','🙃','😉','😌','😍','🥰',
      '😘','😗','😙','😚','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨',
      '😐','😑','😶','😏','😒','🙄','😬','😮‍💨','🤥','😌','😔','😪','🤤','😴','😷','🤒',
      '🤕','🤢','🤮','🥵','🥶','🥴','😵','🤯','🤠','🥳','😎','🤓','🧐','😕','😟','🙁',
      '😮','😯','😲','😳','🥺','😦','😧','😨','😰','😥','😢','😭','😱','😖','😣','😞',
      '😓','😩','😫','🥱','😤','😡','😠','🤬','😈','👿','💀','💩','🤡','👻','👽','🤖',
      // أيدي وأشخاص
      '👍','👎','👌','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','👇','☝️','✋','🤚','🖐️',
      '👋','🤝','👏','🙌','👐','🙏','💪','🦾','🖕','✍️','🤳','💅','👀','👁️','👅','👄',
      // قلوب ورموز
      '❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗','💖',
      '💘','💝','💯','💢','💥','💫','💦','💨','🔥','⭐','🌟','✨','⚡','☀️','🌙','🌈',
      // طبيعة وطعام وأشياء
      '🌹','🌸','🌺','🌻','🌼','🌷','🍀','🌴','🐱','🐶','🦁','🐴','🦋','🐝','🍎','🍉',
      '🍕','🍔','🍟','☕','🍫','🎂','🎁','🎉','🎊','🎈','🎵','🎧','⚽','🚗','✈️','🏠',
      '📱','💻','📷','💡','💰','🔑','🔒','📌','📞','✅','❌','⚠️','❓','❗','➕','➖',
    ];
    // (رمز، تعليق) ملصقات برمز كبير وتعليق قصير
    const captioned = [
      ['❤️', 'أحبك'], ['😍', 'يا سلام'], ['🥰', 'اشتقت لك'], ['😘', 'تسلم'],
      ['🙏', 'شكراً'], ['🤝', 'اتفقنا'], ['👍', 'تمام'], ['👏', 'أحسنت'],
      ['💪', 'قوي'], ['🔥', 'نار'], ['🎉', 'مبروك'], ['🎂', 'عيد ميلاد سعيد'],
      ['🌹', 'لك وردة'], ['☕', 'قهوة؟'], ['😴', 'تصبح على خير'], ['☀️', 'صباح الخير'],
      ['🌙', 'مساء الخير'], ['😂', 'ههههه'], ['🤣', 'مت ضحكاً'], ['😭', 'حزين'],
      ['😡', 'زعلان'], ['🤔', 'ممم؟'], ['🙄', 'ياربي'], ['😎', 'أنا بخير'],
      ['👋', 'مرحباً'], ['🤗', 'تعال'], ['😱', 'مستحيل'], ['🥳', 'نحتفل'],
      ['✅', 'تم'], ['⏳', 'لحظة'], ['📞', 'اتصل بي'], ['🚗', 'في الطريق'],
      ['🏠', 'وصلت'], ['🍕', 'جوعان'], ['🤝', 'أبشر'], ['🙌', 'الحمد لله'],
    ];
    const plain = [
      '😂','🤣','😍','🥰','😘','😭','😡','😱','🤯','🥳','😎','🤩','😴','🤔','🙄','😇',
      '👍','👏','🙏','💪','🔥','❤️','💔','🎉','🌹','🌸','🌻','🎂','🎁','☕','🍕','🚀',
      '🐱','🐶','🦁','🦋','🌈','⭐','💯','👑','💎','🎈','🍫','🍉',
    ];
    Widget emojiGrid(void Function(String) onTap) => GridView.count(
          crossAxisCount: 8,
          padding: const EdgeInsets.all(12),
          children: [
            for (final e in emojis)
              InkWell(
                onTap: () => onTap(e),
                child: Center(child: Text(e, style: const TextStyle(fontSize: 28))),
              ),
          ],
        );
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.5,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(tabs: [Tab(text: 'إيموجي'), Tab(text: 'ملصقات')]),
              Expanded(
                child: TabBarView(
                  children: [
                    emojiGrid((e) {
                      final t = _ctrl.text;
                      final sel = _ctrl.selection;
                      final at = (sel.isValid && sel.start >= 0) ? sel.start : t.length;
                      _ctrl.text = t.substring(0, at) + e + t.substring(at);
                      _ctrl.selection = TextSelection.collapsed(offset: at + e.length);
                      _onChanged(_ctrl.text);
                    }),
                    GridView.count(
                      crossAxisCount: 4,
                      padding: const EdgeInsets.all(12),
                      mainAxisSpacing: 6,
                      children: [
                        for (final c in captioned)
                          InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              _addMessage({'type': 'sticker', 'text': c[0], 'caption': c[1]},
                                  '${c[0]} ${c[1]}');
                            },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(c[0], style: const TextStyle(fontSize: 38)),
                                Text(c[1],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                        for (final e in plain)
                          InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              _addMessage({'type': 'sticker', 'text': e}, '$e ملصق');
                            },
                            child: Center(child: Text(e, style: const TextStyle(fontSize: 44))),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final showSend = _hasText || _editingId != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: dark ? AppColors.otherDark : Colors.white,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined),
                      onPressed: _emojiSheet,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        onChanged: _onChanged,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'رسالة',
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                        ),
                      ),
                    ),
                    if (_sendingMedia)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.image_outlined),
                        onPressed:
                            _editingId != null ? null : () => _pickImage(ImageSource.gallery),
                      ),
                    if (!showSend)
                    IconButton(
                      icon: const Icon(Icons.photo_camera_outlined),
                      onPressed:
                          _editingId != null ? null : () => _pickImage(ImageSource.camera),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.accent,
              child: IconButton(
                color: Colors.white,
                onPressed: showSend ? _send : _startRec,
                icon: Icon(showSend ? (_editingId != null ? Icons.check : Icons.send) : Icons.mic),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Base64Image extends StatefulWidget {
  final String data;
  const _Base64Image(this.data);

  @override
  State<_Base64Image> createState() => _Base64ImageState();
}

class _Base64ImageState extends State<_Base64Image> {
  late final Uint8List _bytes = base64Decode(widget.data);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ImageViewerScreen(bytes: _bytes)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minWidth: 170, maxWidth: 260, maxHeight: 340),
          child: Image.memory(_bytes, fit: BoxFit.cover, gaplessPlayback: true),
        ),
      ),
    );
  }
}
