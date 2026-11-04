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
import 'app_colors.dart';
import 'audio_bubble.dart';
import 'forward_screen.dart';
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
  String? _replyText;
  String? _editingId;
  bool _sendingMedia = false;
  bool _hasText = false;
  bool _typing = false;
  Timer? _typingTimer;
  bool _searching = false;
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
      final bytes = await x.readAsBytes();
      if (bytes.length > _maxMediaBytes) {
        _snack('الصورة كبيرة، اختر صورة أصغر');
        return;
      }
      setState(() => _sendingMedia = true);
      await _addMessage(
          {'type': 'image', 'image': base64Encode(bytes), 'text': ''}, '📷 صورة');
    } catch (_) {
      _snack('تعذر إرسال الصورة');
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  void _attachSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('المعرض'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('الكاميرا'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
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
                  doc.reference.update({
                    'deletedFor': FieldValue.arrayUnion([_uid])
                  });
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

  void _openInfo() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => ChatInfoScreen(chatId: widget.chatId)));

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
          body: Container(
            color: dark ? AppColors.chatBgDark : AppColors.chatBgLight,
            child: Column(
              children: [
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
    } else {
      final otherId = _others.isEmpty ? _uid : _others.first;
      final names = Map<String, dynamic>.from(_chat['names'] ?? {});
      callTitle = (names[otherId] ?? 'مستخدم').toString();
      title = UserBuilder(
        uid: otherId,
        builder: (_, u) => header((u['name'] ?? callTitle).toString(),
            u['photo'] as String?, typing ?? presenceText(u)),
      );
    }

    return AppBar(
      titleSpacing: 0,
      title: title,
      actions: [
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
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'search') {
              setState(() => _searching = true);
            } else {
              _openInfo();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'search', child: Text('بحث')),
            PopupMenuItem(value: 'info', child: Text('معلومات')),
          ],
        ),
      ],
    );
  }

  Widget _messages(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _msgStream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        _markRead(snap.data!.docs);
        var docs = snap.data!.docs
            .where((d) =>
                !List<String>.from(d.data()['deletedFor'] ?? const []).contains(_uid))
            .toList();
        if (_searching && _q.isNotEmpty) {
          docs = docs.where((d) => (d.data()['text'] ?? '').toString().contains(_q)).toList();
        }
        DateTime dt(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            (d.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        if (docs.isEmpty) {
          return Center(child: Text(_searching ? 'لا نتائج' : 'ابدأ المحادثة 👋'));
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(8),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final showDay = i == docs.length - 1 || !sameDay(dt(docs[i]), dt(docs[i + 1]));
            return Column(
              children: [
                if (showDay) _dayChip(context, dayLabel(dt(docs[i]))),
                _bubble(context, docs[i]),
              ],
            );
          },
        );
      },
    );
  }

  Widget _dayChip(BuildContext context, String label) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? AppColors.otherDark : Colors.white70,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Color _nameColor(String uid) {
    const colors = [
      Color(0xFFE65100), Color(0xFF6A1B9A), Color(0xFF00838F),
      Color(0xFFC62828), Color(0xFF2E7D32), Color(0xFF1565C0),
    ];
    return colors[uid.hashCode.abs() % colors.length];
  }

  Widget _bubble(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final data = d.data();
    final senderId = data['senderId'] as String?;
    final mine = senderId == _uid;
    final ts = data['createdAt'] as Timestamp?;
    final reply = data['replyText'] as String?;
    final type = (data['type'] ?? 'text') as String;
    final isImage = type == 'image';
    final readBy = List<String>.from(data['readBy'] ?? const []);
    final readAll = _others.isNotEmpty && _others.every(readBy.contains);
    final time = ts == null ? '' : hhmm(ts.toDate());
    final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});

    Widget content;
    if (isImage) {
      content = _Base64Image(data['image'] as String);
    } else if (type == 'audio') {
      content = AudioBubble(
          data: data['audio'] as String, seconds: (data['duration'] ?? 0) as int);
    } else {
      content = Text(data['text'] ?? '', style: const TextStyle(fontSize: 15.5));
    }

    return Align(
      alignment: mine ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: GestureDetector(
        onLongPress: () => _options(d),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.all(isImage ? 4 : 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: mine
                ? (dark ? AppColors.mineDark : AppColors.mineLight)
                : (dark ? AppColors.otherDark : AppColors.otherLight),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (data['forwarded'] == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('↪ محوّلة',
                      style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).hintColor)),
                ),
              if (_isGroup && !mine && senderId != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(isImage ? 6 : 0, isImage ? 2 : 0, 0, 2),
                  child: Text((data['senderName'] ?? '').toString(),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: _nameColor(senderId))),
                ),
              if (reply != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                        start: BorderSide(color: scheme.primary, width: 3)),
                    color: scheme.primary.withOpacity(0.08),
                  ),
                  child: Text(reply,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              content,
              const SizedBox(height: 2),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isImage ? 6 : 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (reactions.isNotEmpty)
                      Container(
                        margin: const EdgeInsetsDirectional.only(end: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: scheme.surface.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${reactions.values.toSet().join(' ')}${reactions.length > 1 ? ' ${reactions.length}' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    Text(
                      '${data['edited'] == true ? 'معدّلة · ' : ''}$time',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
                    ),
                    if (mine) ...[
                      const SizedBox(width: 4),
                      Icon(
                        ts == null
                            ? Icons.access_time
                            : (readAll ? Icons.done_all : Icons.done),
                        size: 15,
                        color: readAll ? const Color(0xFF34B7F1) : Theme.of(context).hintColor,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _replyBar(BuildContext context) {
    if (_replyText == null && _editingId == null) return const SizedBox.shrink();
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(_editingId != null ? Icons.edit : Icons.reply, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_editingId != null ? 'تعديل الرسالة' : _replyText!,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
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
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        onChanged: _onChanged,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'اكتب رسالة',
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                        icon: const Icon(Icons.attach_file),
                        onPressed: _editingId != null ? null : _attachSheet,
                      ),
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
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
            body: Center(child: InteractiveViewer(child: Image.memory(_bytes))),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(_bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}
