import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import 'app_colors.dart';
import 'phone.dart';
import 'utils.dart';
import 'verify_config.dart';
import 'verify_phone_screen.dart';
import 'widgets.dart';

/// إعداد الملف الشخصي بعد التسجيل (الاسم + نبذة + صورة)، ويُستخدم أيضاً للتعديل
class ProfileSetupScreen extends StatefulWidget {
  final bool isEdit;
  const ProfileSetupScreen({super.key, this.isEdit = false});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _name = TextEditingController();
  final _about = TextEditingController(text: 'مرحباً! أنا أستخدم HaiApp');
  String? _photo;
  PhoneValue? _phone; // الرقم المُدخل (تسجيل جديد)
  String? _savedPhone; // الرقم المحفوظ سابقاً (للعرض فقط ولا يمكن تغييره)
  bool _saving = false;
  bool _taken = false; // الرقم محجوز لحساب آخر
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.text = FirebaseAuth.instance.currentUser?.displayName ?? '';
    if (widget.isEdit) _load();
  }

  Future<void> _load() async {
    final doc = await fs.collection('users').doc(currentUser.uid).get();
    final d = doc.data();
    if (d == null || !mounted) return;
    setState(() {
      _name.text = d['name'] ?? '';
      _about.text = d['about'] ?? '';
      _photo = d['photo'] as String?;
      final ph = (d['phone'] ?? '').toString();
      _savedPhone = ph.isEmpty ? null : ph;
    });
  }

  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 320, maxHeight: 320, imageQuality: 70);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() => _photo = base64Encode(bytes));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'اكتب اسمك (حرفان على الأقل)');
      return;
    }
    // الرقم إلزامي في التسجيل الأول، ولا يتغير بعد حفظه
    final needsPhone = _savedPhone == null;
    final phone = _phone;
    if (needsPhone && (phone == null || !phone.valid)) {
      setState(() => _error = 'اكتب رقم موبايلك مع اختيار رمز الدولة');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _taken = false;
    });
    try {
      await currentUser.updateDisplayName(name);
      final profile = <String, dynamic>{
        'name': name,
        'about': _about.text.trim(),
        'photo': _photo ?? '',
        'online': true,
        'lastSeen': FieldValue.serverTimestamp(),
      };
      if (needsPhone) {
        // يحجز الرقم ويحفظ الملف في عملية واحدة، ويرفض الرقم المكرر
        await claimPhoneAndSaveProfile(phone!, profile);
      } else {
        await fs.collection('users').doc(currentUser.uid).set(profile, SetOptions(merge: true));
      }
      if (widget.isEdit && mounted) Navigator.pop(context);
    } on PhoneTakenException {
      if (mounted) {
        setState(() {
          _error = 'هذا الرقم مسجّل بحساب آخر';
          _taken = true;
        });
      }
    } on FirebaseException catch (e) {
      if (mounted) setState(() => _error = 'تعذر الحفظ [${e.code}] ${e.message ?? ''}');
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
        title: Text(widget.isEdit ? 'الملف الشخصي' : 'معلومات ملفك الشخصي'),
        actions: [
          if (!widget.isEdit)
            IconButton(
                tooltip: 'تسجيل خروج',
                icon: const Icon(Icons.logout),
                onPressed: signOutUser),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickPhoto,
              child: Stack(
                children: [
                  Avatar(photo: _photo, name: _name.text, radius: 64),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.accent,
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _name,
              maxLength: 25,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'الاسم',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _about,
              maxLength: 80,
              decoration: const InputDecoration(
                  labelText: 'النبذة',
                  prefixIcon: Icon(Icons.info_outline),
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            if (_savedPhone != null)
              InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'رقم الموبايل',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder()),
                child: Directionality(
                    textDirection: TextDirection.ltr, child: Text(_savedPhone!)),
              )
            else
              PhoneInput(
                enabled: !_saving,
                onChanged: (v) => _phone = v,
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (_taken && (kTelegramBot.isNotEmpty || kWhatsAppNumber.isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('هذا رقمي، أريد توثيقه ونقله لحسابي'),
                  onPressed: () async {
                    final pv = _phone;
                    if (pv == null) return;
                    final ok = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => VerifyPhoneScreen(phone: pv, claim: true)));
                    if (ok == true && mounted) {
                      setState(() {
                        _savedPhone = pv.e164;
                        _taken = false;
                        _error = null;
                      });
                    }
                  },
                ),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
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
                    : Text(widget.isEdit ? 'حفظ' : 'التالي'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
