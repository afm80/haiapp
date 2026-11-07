import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;

import 'agora_config.dart';

/// الإشعارات: حفظ رمز الجهاز، وطلب إرسال إشعار للطرف الآخر عبر الخادم
class Push {
  static StreamSubscription? _refresh;

  static DocumentReference<Map<String, dynamic>>? get _ref {
    final u = FirebaseAuth.instance.currentUser;
    return u == null ? null : FirebaseFirestore.instance.collection('tokens').doc(u.uid);
  }

  static Future<void> init() async {
    try {
      final m = FirebaseMessaging.instance;
      await m.requestPermission();
      final t = await m.getToken();
      if (t != null) await _save(t);
      _refresh?.cancel();
      _refresh = m.onTokenRefresh.listen(_save);
    } catch (_) {}
  }

  static Future<void> _save(String t) async {
    await _ref?.set({
      'list': FieldValue.arrayUnion([t]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// عند تسجيل الخروج: لا تصل إشعارات هذا الحساب لهذا الجهاز
  static Future<void> clear() async {
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null) await _ref?.set({'list': FieldValue.arrayRemove([t])}, SetOptions(merge: true));
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _refresh?.cancel();
  }

  /// يطلب من الخادم إرسال إشعار (بدون انتظار، وأي فشل يُهمل)
  static void notify(Map<String, dynamic> body) {
    () async {
      try {
        if (kCallsWorkerUrl.isEmpty) return;
        final idToken = await FirebaseAuth.instance.currentUser!.getIdToken();
        await http
            .post(Uri.parse('$kCallsWorkerUrl/notify'),
                headers: {
                  'Authorization': 'Bearer $idToken',
                  'content-type': 'application/json',
                },
                body: jsonEncode(body))
            .timeout(const Duration(seconds: 15));
      } catch (_) {}
    }();
  }
}
