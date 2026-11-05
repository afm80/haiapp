import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';

import 'contacts_service.dart';

final fs = FirebaseFirestore.instance;
User get currentUser => FirebaseAuth.instance.currentUser!;

String chatIdFor(String a, String b) {
  final ids = [a, b]..sort();
  return ids.join('_');
}

String initial(String name) {
  final n = name.trim();
  return n.isEmpty ? '?' : n.characters.first;
}

String hhmm(DateTime d) => DateFormat('HH:mm').format(d);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'أمس';
  return DateFormat('d MMMM yyyy', 'ar').format(d);
}

String chatTime(Timestamp? ts) {
  if (ts == null) return '';
  final d = ts.toDate();
  if (sameDay(d, DateTime.now())) return hhmm(d);
  final diff = DateTime.now().difference(d).inDays;
  if (diff <= 1) return 'أمس';
  return DateFormat('d/M/yyyy').format(d);
}

/// متصل إذا آخر نبضة خلال دقيقتين
String presenceText(Map<String, dynamic> u) {
  final ts = u['lastSeen'] as Timestamp?;
  if (ts == null) return '';
  final d = ts.toDate();
  if (u['online'] == true && DateTime.now().difference(d).inMinutes < 2) {
    return 'متصل';
  }
  return 'آخر ظهور ${dayLabel(d)} ${hhmm(d)}';
}

final _photoCache = <int, Uint8List>{};
Uint8List decodePhoto(String s) =>
    _photoCache.putIfAbsent(s.hashCode ^ s.length, () => base64Decode(s));

Future<void> setPresence(bool online) async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) return;
  try {
    await fs.collection('users').doc(u.uid).set(
        {'online': online, 'lastSeen': FieldValue.serverTimestamp()},
        SetOptions(merge: true));
  } catch (_) {}
}

Future<void> signOutUser() async {
  await setPresence(false);
  ContactsService.clear();
  try {
    await GoogleSignIn().signOut();
  } catch (_) {}
  await FirebaseAuth.instance.signOut();
}

String previewOf(Map<String, dynamic> m) {
  switch (m['type']) {
    case 'image':
      return '📷 صورة';
    case 'audio':
      return '🎤 رسالة صوتية';
    default:
      return (m['text'] ?? '').toString();
  }
}

String mmss(int s) =>
    '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
