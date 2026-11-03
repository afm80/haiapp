import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String title;
  const ChatScreen({super.key, required this.chatId, required this.title});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _maxImageBytes = 700 * 1024; // حد مستند Firestore ~1MB
  final _ctrl = TextEditingController();
  final _me = FirebaseAuth.instance.currentUser!;
  String? _replyText;
  String? _editingId;
  bool _sendingImage = false;

  DocumentReference<Map<String, dynamic>> get _chat =>
      FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
  CollectionReference<Map<String, dynamic>> get _msgs =>
      _chat.collection('messages');

  Future<void> _updateLast(String preview) => _chat.update({
        'lastMessage': preview,
        'lastMessageAt': FieldValue.serverTimestamp(),
      });

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();

    if (_editingId != null) {
      final id = _editingId!;
      setState(() => _editingId = null);
      await _msgs.doc(id).update({'text': text, 'edited': true});
      return;
    }

    final reply = _replyText;
    setState(() => _replyText = null);
    await _msgs.add({
      'type': 'text',
      'text': text,
      'senderId': _me.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'replyText': reply,
      'edited': false,
      'read': false,
    });
    await _updateLast(text);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final x = await ImagePicker()
          .pickImage(source: source, maxWidth: 1024, imageQuality: 60);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (bytes.length > _maxImageBytes) {
        _snack('الصورة كبيرة، اختر صورة أصغر');
        return;
      }
      setState(() => _sendingImage = true);
      final reply = _replyText;
      setState(() => _replyText = null);
      await _msgs.add({
        'type': 'image',
        'image': base64Encode(bytes),
        'text': '',
        'senderId': _me.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'replyText': reply,
        'edited': false,
        'read': false,
      });
      await _updateLast('📷 صورة');
    } catch (_) {
      _snack('تعذر إرسال الصورة');
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  void _attachSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('المعرض'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('الكاميرا'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // علّم رسائل الطرف الثاني كمقروءة
  void _markRead(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final unread = docs
        .where((d) => d['senderId'] != _me.uid && d.data()['read'] != true)
        .toList();
    if (unread.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final batch = FirebaseFirestore.instance.batch();
      for (final d in unread) {
        batch.update(d.reference, {'read': true});
      }
      batch.commit().catchError((_) {});
    });
  }

  void _options(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final mine = doc['senderId'] == _me.uid;
    final isImage = doc.data()['type'] == 'image';
    final text = (doc.data()['text'] ?? '') as String;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('رد'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _replyText = isImage ? '📷 صورة' : text;
                  _editingId = null;
                });
              },
            ),
            if (!isImage)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('نسخ'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: text));
                },
              ),
            if (mine && !isImage)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('تعديل'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _editingId = doc.id;
                    _replyText = null;
                    _ctrl.text = text;
                  });
                },
              ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('حذف'),
                onTap: () {
                  Navigator.pop(context);
                  doc.reference.delete();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _msgs
                  .orderBy('createdAt', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                _markRead(docs);
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: docs.length,
                  itemBuilder: (context, i) => _bubble(docs[i], scheme),
                );
              },
            ),
          ),
          if (_replyText != null || _editingId != null)
            Container(
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(_editingId != null ? Icons.edit : Icons.reply, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _editingId != null ? 'تعديل الرسالة' : _replyText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
              child: Row(
                children: [
                  _sendingImage
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          icon: const Icon(Icons.attach_file),
                          onPressed: _editingId != null ? null : _attachSheet,
                        ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالة...',
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _send,
                    icon: Icon(_editingId != null ? Icons.check : Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(
      QueryDocumentSnapshot<Map<String, dynamic>> d, ColorScheme scheme) {
    final data = d.data();
    final mine = data['senderId'] == _me.uid;
    final ts = data['createdAt'] as Timestamp?;
    final reply = data['replyText'] as String?;
    final isImage = data['type'] == 'image';
    final read = data['read'] == true;
    final time = ts == null ? '' : DateFormat('HH:mm').format(ts.toDate());

    return Align(
      alignment: mine
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: GestureDetector(
        onLongPress: () => _options(d),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: EdgeInsets.all(isImage ? 4 : 10),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: mine
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reply != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border(
                        right: BorderSide(color: scheme.primary, width: 3)),
                    color: scheme.primary.withOpacity(0.08),
                  ),
                  child: Text(reply,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              if (isImage)
                _Base64Image(data['image'] as String)
              else
                Text(data['text'] ?? ''),
              const SizedBox(height: 2),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isImage ? 6 : 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${data['edited'] == true ? 'معدّلة · ' : ''}$time',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    if (mine) ...[
                      const SizedBox(width: 4),
                      Icon(
                        ts == null
                            ? Icons.access_time
                            : (read ? Icons.done_all : Icons.done),
                        size: 14,
                        color: read ? Colors.blue : scheme.outline,
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
            appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white),
            body: Center(
              child: InteractiveViewer(child: Image.memory(_bytes)),
            ),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(_bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}
