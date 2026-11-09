import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app_colors.dart';
import 'google_config.dart';

/// شاشة واحدة: ترحيب + الموافقة + الدخول بحساب Google.
/// الدخول يتم بنافذة اختيار الحساب الأصلية داخل التطبيق (بدون فتح المتصفح).
/// عند حدوث خطأ يظهر رمزه على الشاشة (بدون فتح المتصفح).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _loading = false;
  String? _error;

  /// يرجع false إذا ألغى المستخدم
  Future<bool> _native() async {
    final gs = GoogleSignIn(scopes: ['email'], serverClientId: kGoogleWebClientId);
    await gs.signOut(); // ليظهر اختيار الحساب في كل مرة
    final acc = await gs.signIn();
    if (acc == null) return false;
    final auth = await acc.authentication;
    if (auth.idToken == null) {
      throw FirebaseAuthException(code: 'missing-id-token');
    }
    await FirebaseAuth.instance.signInWithCredential(GoogleAuthProvider.credential(
        accessToken: auth.accessToken, idToken: auth.idToken));
    return true;
  }

  Future<void> _google() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _native();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = '${_arabicError(e.code)}\n[${e.code}] ${e.message ?? ''}');
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = 'تعذر تسجيل الدخول\n[${e.code}] ${e.message ?? ''}');
    } catch (e) {
      if (mounted) setState(() => _error = 'صار خطأ، حاول مرة ثانية\n$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _arabicError(String code) {
    switch (code) {
      case 'network-request-failed':
        return 'تأكد من اتصالك بالإنترنت';
      case 'web-context-canceled':
      case 'canceled':
      case 'popup-closed-by-user':
        return 'تم إلغاء تسجيل الدخول';
      case 'account-exists-with-different-credential':
        return 'هذا الإيميل مسجل بطريقة دخول أخرى';
      case 'operation-not-allowed':
        return 'تسجيل الدخول بـ Google غير مفعّل في Firebase';
      default:
        return 'صار خطأ، حاول مرة ثانية';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const onDark = Colors.white;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF7A0A3C), Color(0xFF5F012B), Color(0xFF2E0115)],
          ),
        ),
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: Image.asset('assets/icon/icon.png', width: 160, height: 160),
              ),
              const SizedBox(height: 28),
              Text('مرحباً بك في HaiApp',
                  style: t.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: onDark)),
              const SizedBox(height: 10),
              Text('تواصل مع أصدقائك وعائلتك بسهولة وخصوصية،\nرسائل وصور ومجموعات وحالات ومكالمات.',
                  textAlign: TextAlign.center,
                  style: t.bodyLarge?.copyWith(color: Colors.white70)),
              const Spacer(),
              if (_error != null) ...[
                SelectableText(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFFB4C8))),
                const SizedBox(height: 12),
              ],
              Text('بالمتابعة فأنت توافق على شروط الاستخدام وسياسة الخصوصية.',
                  textAlign: TextAlign.center,
                  style: t.bodySmall?.copyWith(color: Colors.white60)),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  onPressed: _loading ? null : _google,
                  icon: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.login),
                  label: const Text('الموافقة والمتابعة بحساب Google'),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
