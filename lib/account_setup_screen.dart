import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'auth_api.dart';
import 'username.dart';
import 'utils.dart';

/// بعد دخول Google: اليوزرنيم + كلمة مرور HaiChat.
/// isEdit = تغيير كلمة المرور فقط (من الإعدادات).
class AccountSetupScreen extends StatefulWidget {
  final bool isEdit;
  const AccountSetupScreen({super.key, this.isEdit = false});

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _hasUsername = false;
  bool _loaded = false;
  bool _saving = false;
  bool _hide = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = (await fs.collection('users').doc(currentUser.uid).get()).data();
    final un = (d?['username'] ?? '').toString();
    if (!mounted) return;
    setState(() {
      _hasUsername = un.isNotEmpty;
      _user.text = un;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final un = _user.text.trim().toLowerCase();
    final p = _pass.text;
    if (!_hasUsername && !widget.isEdit) {
      final e = validateUsername(un);
      if (e != null) {
        setState(() => _error = 'اليوزرنيم: $e');
        return;
      }
    }
    if (p.length < 8) {
      setState(() => _error = 'كلمة المرور 8 أحرف على الأقل');
      return;
    }
    if (p != _pass2.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!_hasUsername && !widget.isEdit) {
        if (!await usernameAvailable(un)) {
          setState(() => _error = 'هذا اليوزرنيم مستخدم، اختر غيره');
          return;
        }
        await saveUsername(un);
      }
      await setHaiChatPassword(p);
      if (widget.isEdit && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم حفظ كلمة المرور')));
        Navigator.pop(context);
      }
    } on UsernameTakenException {
      if (mounted) setState(() => _error = 'هذا اليوزرنيم مستخدم، اختر غيره');
    } on AuthApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر الحفظ، حاول مرة ثانية\n$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'كلمة المرور' : 'إكمال الحساب'),
        actions: [
          if (!widget.isEdit)
            IconButton(
                tooltip: 'تسجيل خروج', icon: const Icon(Icons.logout), onPressed: signOutUser),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.isEdit
                        ? 'اختر كلمة مرور جديدة لـ HaiChat.'
                        : 'خطوة أخيرة: اختر يوزرنيم وكلمة مرور لتدخل بهما إذا نسيت حساب Google.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  if (!widget.isEdit)
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextField(
                        controller: _user,
                        enabled: !_hasUsername && !_saving,
                        autocorrect: false,
                        decoration: const InputDecoration(
                            labelText: 'اليوزرنيم',
                            prefixText: '@',
                            border: OutlineInputBorder()),
                      ),
                    ),
                  if (!widget.isEdit) const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: _hide,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      labelText: 'كلمة مرور HaiChat (غير كلمة مرور Google)',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass2,
                    obscureText: _hide,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                        labelText: 'أعد كتابة كلمة المرور',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder()),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(widget.isEdit ? 'حفظ' : 'متابعة'),
                  ),
                ],
              ),
            ),
    );
  }
}
