import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_colors.dart';
import 'phone.dart';
import 'utils.dart';
import 'verify_config.dart';

/// الرقم المحفوظ في ملف المستخدم كـ PhoneValue (أو null)
PhoneValue? phoneValueFromUser(Map<String, dynamic> u) {
  final key = (u['phoneKey'] ?? '').toString().isNotEmpty
      ? u['phoneKey'].toString()
      : (u['phone'] ?? '').toString().replaceAll('+', '');
  if (key.isEmpty) return null;
  final cc = (u['phoneCountry'] ?? '').toString();
  final country = countries.firstWhere((c) => c.code == cc,
      orElse: () => countries.firstWhere((c) => key.startsWith(c.code),
          orElse: () => countries.first));
  if (!key.startsWith(country.code)) return null;
  return PhoneValue(country, key.substring(country.code.length));
}

/// توثيق ملكية الرقم عبر تيليجرام أو واتساب (اختياري).
/// claim = true: الرقم محجوز لحساب آخر غير موثّق وأنا صاحبه الحقيقي.
/// يرجع true عند نجاح التوثيق.
class VerifyPhoneScreen extends StatefulWidget {
  final PhoneValue phone;
  final bool claim;
  const VerifyPhoneScreen({super.key, required this.phone, this.claim = false});

  @override
  State<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends State<VerifyPhoneScreen> {
  StreamSubscription? _sub;
  bool _busy = false;
  bool _waiting = false;
  String? _error;

  bool get _telegramOn => kTelegramBot.isNotEmpty;
  bool get _whatsappOn => kWhatsAppNumber.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // عندما يكمل الخادم التوثيق يتحدّث ملفك فنغلق الشاشة تلقائياً
    _sub = fs.collection('users').doc(currentUser.uid).snapshots().listen((s) {
      final d = s.data();
      if (d != null &&
          d['phoneVerified'] == true &&
          d['phoneKey'] == widget.phone.key &&
          mounted) {
        Navigator.pop(context, true);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _newCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    return List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _start(bool telegram) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = _newCode();
      await fs.collection('verifications').doc(code).set({
        'uid': currentUser.uid,
        'phoneKey': widget.phone.key,
        'country': widget.phone.country.code,
        'claim': widget.claim,
        'createdAt': FieldValue.serverTimestamp(),
      });
      final uri = telegram
          ? Uri.parse('https://t.me/$kTelegramBot?start=$code')
          : Uri.parse(
              'https://wa.me/$kWhatsAppNumber?text=${Uri.encodeComponent('HaiApp $code')}');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) setState(() => _waiting = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر بدء التوثيق، حاول مرة ثانية');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(title: const Text('توثيق الرقم')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.verified_user_outlined, size: 64, color: AppColors.primary),
          const SizedBox(height: 16),
          Center(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(widget.phone.e164,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.claim
                ? 'هذا الرقم مسجّل بحساب آخر غير موثّق. إن كان رقمك فعلاً، وثّقه الآن '
                    'ليُنقل إلى حسابك.'
                : 'وثّق رقمك لإثبات أنه يخصّك، وتظهر بجانب رقمك علامة "موثّق".',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text('يجب أن تستخدم التطبيق الذي عليه نفس الرقم.',
              textAlign: TextAlign.center, style: TextStyle(color: hint)),
          const SizedBox(height: 28),
          if (!_telegramOn && !_whatsappOn)
            Text('التوثيق غير مفعّل بعد في هذه النسخة.',
                textAlign: TextAlign.center, style: TextStyle(color: hint)),
          if (_telegramOn)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _busy ? null : () => _start(true),
              icon: const Icon(Icons.send),
              label: const Text('التوثيق عبر تيليجرام'),
            ),
          if (_telegramOn && _whatsappOn) const SizedBox(height: 12),
          if (_whatsappOn)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _busy ? null : () => _start(false),
              icon: const Icon(Icons.chat),
              label: const Text('التوثيق عبر واتساب'),
            ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_waiting) ...[
            const SizedBox(height: 28),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            Text('أكمل الخطوات في التطبيق الذي فتح، ثم ارجع إلى هنا. سيتحدّث الحساب تلقائياً.',
                textAlign: TextAlign.center, style: TextStyle(color: hint)),
          ],
        ],
      ),
    );
  }
}
