import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'username.dart';
import 'utils.dart';

/// اختيار اسم المستخدم (@username) ليجدك الناس بدون رقمك
class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _ctrl = TextEditingController();
  String _current = '';
  String? _msg;
  bool _ok = false;
  bool _checking = false;
  bool _saving = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    fs.collection('users').doc(currentUser.uid).get().then((d) {
      final u = (d.data()?['username'] ?? '').toString();
      if (!mounted) return;
      setState(() => _current = u);
      _ctrl.text = u;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _changed(String raw) {
    final v = raw.trim().toLowerCase();
    _debounce?.cancel();
    setState(() {
      _ok = false;
      _msg = null;
    });
    if (v.isEmpty || v == _current) return;
    final bad = validateUsername(v);
    if (bad != null) {
      setState(() => _msg = bad);
      return;
    }
    setState(() => _checking = true);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final free = await usernameAvailable(v);
        if (!mounted || _ctrl.text.trim().toLowerCase() != v) return;
        setState(() {
          _checking = false;
          _ok = free;
          _msg = free ? 'الاسم متاح' : 'هذا الاسم مستخدم';
        });
      } catch (_) {
        if (mounted) setState(() => _checking = false);
      }
    });
  }

  Future<void> _save() async {
    final v = _ctrl.text.trim().toLowerCase();
    setState(() => _saving = true);
    try {
      await saveUsername(v);
      if (mounted) Navigator.pop(context);
    } on UsernameTakenException {
      if (mounted) setState(() => _msg = 'هذا الاسم مستخدم');
    } on FirebaseException catch (e) {
      if (mounted) setState(() => _msg = 'تعذر الحفظ [${e.code}]');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    try {
      await removeUsername();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _msg = 'تعذر الحذف');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    final err = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: const Text('اسم المستخدم')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'اختر اسماً فريداً يستطيع الناس البحث به للتواصل معك بدون معرفة رقمك.',
          ),
          const SizedBox(height: 16),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _ctrl,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              onChanged: _changed,
              decoration: InputDecoration(
                prefixText: '@',
                hintText: 'username',
                border: const OutlineInputBorder(),
                suffixIcon: _checking
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                    : (_ok ? const Icon(Icons.check_circle, color: Colors.green) : null),
              ),
            ),
          ),
          if (_msg != null) ...[
            const SizedBox(height: 8),
            Text(_msg!, style: TextStyle(color: _ok ? Colors.green : err)),
          ],
          const SizedBox(height: 8),
          Text('4 إلى 24 حرفاً: حروف إنجليزية صغيرة وأرقام و _ ، ويبدأ بحرف.',
              style: TextStyle(color: hint, fontSize: 12.5)),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: (_ok && !_saving) ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('حفظ'),
          ),
          if (_current.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : _remove,
              child: Text('حذف اسم المستخدم', style: TextStyle(color: err)),
            ),
          ],
        ],
      ),
    );
  }
}
