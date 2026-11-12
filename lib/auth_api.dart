import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'agora_config.dart';
import 'phone.dart';

/// تحويل ما كتبه المستخدم (رقم أو يوزرنيم) إلى مفتاح للبحث
String normalizeLoginId(String raw) {
  var s = latinDigits(raw).trim().toLowerCase().replaceAll(' ', '');
  if (s.startsWith('@')) s = s.substring(1);
  final isPhone = RegExp(r'^[+0-9]+$').hasMatch(s);
  if (!isPhone) return s;
  if (s.startsWith('+')) return s.replaceAll(RegExp(r'\D'), '');
  if (s.startsWith('00')) return s.substring(2);
  // رقم محلي: نضيف رمز دولة الجهاز
  return '${defaultCountry().code}${nationalDigits(s)}';
}

class AuthApiException implements Exception {
  final String message;
  AuthApiException(this.message);
  @override
  String toString() => message;
}

Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
    {String? idToken}) async {
  try {
    final r = await http
        .post(Uri.parse('$kCallsWorkerUrl/$path'),
            headers: {
              'content-type': 'application/json',
              if (idToken != null) 'authorization': 'Bearer $idToken',
            },
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    Map<String, dynamic> j = {};
    try {
      j = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    if (r.statusCode == 200) return j;
    if (r.statusCode == 401) throw AuthApiException('بيانات الدخول غير صحيحة');
    if (r.statusCode == 429) throw AuthApiException('محاولات كثيرة، انتظر قليلاً ثم حاول');
    if (j['error'] == 'short') throw AuthApiException('كلمة المرور 8 أحرف على الأقل');
    throw AuthApiException('تعذر الإكمال، حاول مرة ثانية');
  } on AuthApiException {
    rethrow;
  } catch (_) {
    throw AuthApiException('تأكد من اتصالك بالإنترنت');
  }
}

/// دخول بالرقم أو اليوزرنيم + كلمة المرور
Future<void> loginWithPassword(String rawId, String password) async {
  final j = await _post('login', {'id': normalizeLoginId(rawId), 'password': password});
  final t = j['token'];
  if (t is! String) throw AuthApiException('بيانات الدخول غير صحيحة');
  await FirebaseAuth.instance.signInWithCustomToken(t);
}

/// يرسل رابط الاستعادة لإيميل Google المرتبط، ويرجع شكلاً مخفياً للإيميل
Future<String> requestReset(String rawId) async {
  final j = await _post('reset', {'id': normalizeLoginId(rawId)});
  return (j['hint'] ?? '').toString();
}

/// تعيين/تغيير كلمة مرور HaiChat لصاحب الجلسة الحالية
Future<void> setHaiChatPassword(String password) async {
  final tok = await FirebaseAuth.instance.currentUser!.getIdToken(true);
  await _post('set-password', {'password': password}, idToken: tok);
}
