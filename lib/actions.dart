import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'call_screen.dart';
import 'call_state.dart';
import 'chat_screen.dart';
import 'utils.dart';

Future<void> openDirectChat(
    BuildContext context, String otherId, String otherName,
    {bool replace = false}) async {
  final uid = currentUser.uid;
  final chatId = chatIdFor(uid, otherId);
  await fs.collection('chats').doc(chatId).set({
    'participants': [uid, otherId]..sort(),
    'isGroup': false,
    'names': {uid: currentUser.displayName ?? '', otherId: otherName},
  }, SetOptions(merge: true));
  if (!context.mounted) return;
  final route = MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId));
  if (replace) {
    Navigator.pushReplacement(context, route);
  } else {
    Navigator.push(context, route);
  }
}

/// المكالمات تتم داخل التطبيق عبر Agora
Future<void> joinCall(BuildContext context, String room, bool video, String title,
    {String? callId, bool oneToOne = true}) async {
  await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => CallScreen(
              room: room,
              video: video,
              title: title,
              callId: callId,
              caller: true,
              oneToOne: oneToOne)));
}

Future<void> startCall(
  BuildContext context, {
  required List<String> calleeIds,
  required String title,
  required bool video,
}) async {
  if (activeCalls > 0) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('أنت في مكالمة الآن')));
    return;
  }
  final uid = currentUser.uid;
  final room =
      'HaiApp-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(99999)}';
  final ref = await fs.collection('calls').add({
    'callerId': uid,
    'callerName': currentUser.displayName ?? '',
    'calleeIds': calleeIds,
    'participants': [uid, ...calleeIds],
    'title': title,
    'type': video ? 'video' : 'voice',
    'room': room,
    'status': 'ringing',
    'createdAt': FieldValue.serverTimestamp(),
  });
  if (!context.mounted) return;
  await joinCall(context, room, video, title,
      callId: ref.id, oneToOne: calleeIds.length == 1);
}

/// إرسال رسالة لمحادثة (يُستخدم في الإرسال العادي والتحويل)
Future<void> sendToChat(String chatId, List<String> participants,
    Map<String, dynamic> data, String preview) async {
  final uid = currentUser.uid;
  final name = currentUser.displayName ?? '';
  final chat = fs.collection('chats').doc(chatId);
  await chat.collection('messages').add({
    'edited': false,
    'readBy': <String>[],
    'replyText': null,
    ...data,
    'senderId': uid,
    'senderName': name,
    'createdAt': FieldValue.serverTimestamp(),
  });
  final upd = <String, dynamic>{
    'lastMessage': preview,
    'lastMessageAt': FieldValue.serverTimestamp(),
    'lastSenderId': uid,
    'lastSenderName': name,
  };
  for (final p in participants) {
    if (p != uid) upd['unread.$p'] = FieldValue.increment(1);
  }
  await chat.update(upd);
}
