import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _isLogin = false;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (_isLogin) {
        await auth.signInWithEmailAndPassword(
            email: _email.text.trim(), password: _pass.text);
      } else {
        await auth.createUserWithEmailAndPassword(
            email: _email.text.trim(), password: _pass.text);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _arabicError(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'اكتب إيميلك أولاً ثم اضغط نسيت كلمة المرور');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _email.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('أرسلنا رابط إعادة التعيين إلى إيميلك')));
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _arabicError(e.code));
    }
  }

  String _arabicError(String code) {
    switch (code) {
      case 'invalid-email':
        return 'الإيميل غير صحيح';
      case 'weak-password':
        return 'كلمة المرور ضعيفة (6 أحرف على الأقل)';
      case 'email-already-in-use':
        return 'هذا الإيميل مسجل من قبل، سجّل دخول';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'الإيميل أو كلمة المرور غير صحيحة';
      case 'network-request-failed':
        return 'تأكد من اتصالك بالإنترنت';
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
                  Text(_isLogin ? 'تسجيل الدخول' : 'إنشاء حساب',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'الإيميل', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'كلمة المرور', border: OutlineInputBorder()),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isLogin ? 'دخول' : 'التالي'),
                  ),
                  if (_isLogin)
                    TextButton(onPressed: _reset, child: const Text('نسيت كلمة المرور؟')),
                  TextButton(
                    onPressed: () => setState(() {
                      _isLogin = !_isLogin;
                      _error = null;
                    }),
                    child: Text(_isLogin
                        ? 'ما عندك حساب؟ سجّل الآن'
                        : 'عندك حساب؟ سجّل دخول'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
