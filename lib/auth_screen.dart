import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// تسجيل الدخول بحساب Google فقط.
/// نستخدم signInWithProvider (من firebase_auth نفسها) فلا نحتاج بصمة SHA-1
/// ولا حزمة إضافية، وتعمل حتى لو تغيّر توقيع التطبيق في كل بناء على GitHub.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _google() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..setCustomParameters({'prompt': 'select_account'});
      await FirebaseAuth.instance.signInWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = '${_arabicError(e.code)}\n[${e.code}] ${e.message ?? ''}');
      }
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset('assets/icon/icon.png', width: 88, height: 88),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('تسجيل الدخول',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('سجّل دخولك بحساب Google، ثم أضف رقم موبايلك ليكون هويتك في التطبيق.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _loading ? null : _google,
                    icon: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.login),
                    label: const Text('المتابعة بحساب Google'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
