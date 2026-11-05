import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// المكالمات تتم عبر Jitsi Meet المجاني (مفتوح المصدر)
Future<void> joinCall(String room, bool video) async {
  // disableDeepLinking: يتخطى صفحة "Join in app / Join in browser" ويدخل الاجتماع مباشرة
  final url = Uri.parse('https://meet.jit.si/$room'
      '#config.startWithVideoMuted=${!video}'
      '&config.startWithAudioMuted=false'
      '&config.prejoinPageEnabled=false'
      '&config.disableDeepLinking=true');
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

Future<void> startCall(
  BuildContext context, {
  required List<String> calleeIds,
  required String title,
  required bool video,
}) async {
  final uid = currentUser.uid;
  final room =
      'HaiApp-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(99999)}';
  await fs.collection('calls').add({
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
  await joinCall(room, video);
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
