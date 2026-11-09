import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'phone.dart';
import 'verify_phone_screen.dart';
import 'utils.dart';

/// تغيير رقم الموبايل مثل تلغرام: الحساب والمحادثات تبقى كما هي
class ChangePhoneScreen extends StatefulWidget {
  const ChangePhoneScreen({super.key});

  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  PhoneValue? _phone;
  PhoneValue? _initial;
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    fs.collection('users').doc(currentUser.uid).get().then((d) {
      if (!mounted) return;
      setState(() {
        _initial = phoneValueFromUser(d.data() ?? {});
        _phone = _initial;
        _loaded = true;
      });
    });
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    final p = _phone;
    if (p == null || !p.valid || _saving) return;
    if (_initial != null && p.key == _initial!.key) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    try {
      await changePhone(p);
      if (!mounted) return;
      _snack('تم تغيير رقمك. محادثاتك كما هي');
      Navigator.pop(context);
    } on PhoneTakenException {
      _snack('هذا الرقم مسجل لحساب آخر');
    } catch (_) {
      _snack('تعذر تغيير الرقم، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تغيير الرقم')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                    'اكتب رقمك الجديد. حسابك ومحادثاتك وأصدقاؤك كلها تبقى كما هي، '
                    'ويصبح أصدقاؤك يرونك بالرقم الجديد.'),
                const SizedBox(height: 20),
                PhoneInput(
                  initial: _initial,
                  enabled: !_saving,
                  onChanged: (v) => setState(() => _phone = v),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                  onPressed: (_phone?.valid ?? false) && !_saving ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('حفظ الرقم الجديد'),
                ),
              ],
            ),
    );
  }
}
