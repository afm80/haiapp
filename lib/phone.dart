import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'utils.dart';

/// دولة + رمزها الدولي
class Country {
  final String iso;
  final String name;
  final String code; // بدون +
  const Country(this.iso, this.name, this.code);
}

const countries = <Country>[
  Country('IQ', 'العراق', '964'),
  Country('SA', 'السعودية', '966'),
  Country('AE', 'الإمارات', '971'),
  Country('KW', 'الكويت', '965'),
  Country('QA', 'قطر', '974'),
  Country('BH', 'البحرين', '973'),
  Country('OM', 'عُمان', '968'),
  Country('JO', 'الأردن', '962'),
  Country('SY', 'سوريا', '963'),
  Country('LB', 'لبنان', '961'),
  Country('PS', 'فلسطين', '970'),
  Country('EG', 'مصر', '20'),
  Country('LY', 'ليبيا', '218'),
  Country('TN', 'تونس', '216'),
  Country('DZ', 'الجزائر', '213'),
  Country('MA', 'المغرب', '212'),
  Country('SD', 'السودان', '249'),
  Country('YE', 'اليمن', '967'),
  Country('SO', 'الصومال', '252'),
  Country('MR', 'موريتانيا', '222'),
  Country('TR', 'تركيا', '90'),
  Country('IR', 'إيران', '98'),
  Country('US', 'الولايات المتحدة', '1'),
  Country('CA', 'كندا', '1'),
  Country('GB', 'بريطانيا', '44'),
  Country('DE', 'ألمانيا', '49'),
  Country('FR', 'فرنسا', '33'),
  Country('IT', 'إيطاليا', '39'),
  Country('ES', 'إسبانيا', '34'),
  Country('SE', 'السويد', '46'),
  Country('NL', 'هولندا', '31'),
  Country('NO', 'النرويج', '47'),
  Country('DK', 'الدنمارك', '45'),
  Country('FI', 'فنلندا', '358'),
  Country('CH', 'سويسرا', '41'),
  Country('AT', 'النمسا', '43'),
  Country('BE', 'بلجيكا', '32'),
  Country('GR', 'اليونان', '30'),
  Country('CY', 'قبرص', '357'),
  Country('RU', 'روسيا', '7'),
  Country('UA', 'أوكرانيا', '380'),
  Country('AU', 'أستراليا', '61'),
  Country('NZ', 'نيوزيلندا', '64'),
  Country('IN', 'الهند', '91'),
  Country('PK', 'باكستان', '92'),
  Country('BD', 'بنغلاديش', '880'),
  Country('AF', 'أفغانستان', '93'),
  Country('CN', 'الصين', '86'),
  Country('JP', 'اليابان', '81'),
  Country('KR', 'كوريا الجنوبية', '82'),
  Country('MY', 'ماليزيا', '60'),
  Country('ID', 'إندونيسيا', '62'),
  Country('PH', 'الفلبين', '63'),
  Country('NG', 'نيجيريا', '234'),
  Country('ZA', 'جنوب أفريقيا', '27'),
  Country('KE', 'كينيا', '254'),
  Country('ET', 'إثيوبيا', '251'),
  Country('BR', 'البرازيل', '55'),
  Country('MX', 'المكسيك', '52'),
  Country('AR', 'الأرجنتين', '54'),
];

/// دولة الجهاز إن وُجدت في القائمة، وإلا العراق
Country defaultCountry() {
  final iso = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
  return countries.firstWhere((c) => c.iso == iso, orElse: () => countries.first);
}

/// يحوّل الأرقام العربية/الفارسية إلى لاتينية
String latinDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(r - 0x0660 + 48);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(r - 0x06F0 + 48);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// الرقم المحلي: أرقام فقط وبدون الأصفار في البداية (0770 ← 770)
String nationalDigits(String s) =>
    latinDigits(s).replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');

/// مفتاح الرقم في Firestore: الرمز الدولي + الرقم بدون +
String phoneKey(String e164) => e164.replaceAll('+', '');

class PhoneValue {
  final Country country;
  final String national;
  const PhoneValue(this.country, this.national);

  String get e164 => '+${country.code}$national';
  String get key => '${country.code}$national';
  bool get valid => national.length >= 6 && key.length <= 15;
}

class PhoneTakenException implements Exception {}

/// يحجز الرقم لهذا الحساب ويحفظ بيانات الملف الشخصي في عملية واحدة.
/// إذا كان الرقم محجوزاً لحساب آخر يرمي PhoneTakenException.
Future<void> claimPhoneAndSaveProfile(PhoneValue p, Map<String, dynamic> profile) async {
  final uid = currentUser.uid;
  final phoneRef = fs.collection('phones').doc(p.key);
  final userRef = fs.collection('users').doc(uid);
  try {
    await fs.runTransaction((tx) async {
      final snap = await tx.get(phoneRef);
      final owner = snap.data()?['uid'];
      if (snap.exists && owner != uid) throw PhoneTakenException();
      if (!snap.exists) {
        tx.set(phoneRef, {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
      }
      tx.set(
          userRef,
          {
            ...profile,
            'phone': p.e164,
            'phoneCountry': p.country.code,
            'phoneVerified': false,
          },
          SetOptions(merge: true));
    });
  } on FirebaseException catch (e) {
    // لا نعتبر الرقم مكرراً إلا إذا تأكدنا أنه محجوز فعلاً لحساب آخر
    if (e.code == 'permission-denied' || e.code == 'aborted') {
      try {
        final d = await phoneRef.get();
        final owner = d.data()?['uid'];
        if (d.exists && owner != uid) throw PhoneTakenException();
      } on FirebaseException {
        // تعذرت القراءة: نعرض الخطأ الأصلي بدل رسالة مضللة
      }
    }
    rethrow;
  }
}

/// uid صاحب الرقم أو null إن لم يكن مسجلاً
Future<String?> findUidByPhone(PhoneValue p) async {
  final d = await fs.collection('phones').doc(p.key).get();
  return d.data()?['uid'] as String?;
}

/// حقل إدخال رقم مع اختيار رمز الدولة
class PhoneInput extends StatefulWidget {
  final ValueChanged<PhoneValue> onChanged;
  final bool enabled;
  const PhoneInput({super.key, required this.onChanged, this.enabled = true});

  @override
  State<PhoneInput> createState() => _PhoneInputState();
}

class _PhoneInputState extends State<PhoneInput> {
  final _ctrl = TextEditingController();
  late Country _country = defaultCountry();

  void _emit() => widget.onChanged(PhoneValue(_country, nationalDigits(_ctrl.text)));

  Future<void> _pick() async {
    final c = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CountrySheet(),
    );
    if (c != null) {
      setState(() => _country = c);
      _emit();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 56,
            child: OutlinedButton(
              onPressed: widget.enabled ? _pick : null,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: Text('${_country.iso}  +${_country.code}'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _ctrl,
              enabled: widget.enabled,
              keyboardType: TextInputType.phone,
              onChanged: (_) => _emit(),
              decoration: const InputDecoration(
                  labelText: 'رقم الموبايل',
                  hintText: '7701234567',
                  border: OutlineInputBorder()),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet();

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim();
    final list = countries
        .where((c) => q.isEmpty || c.name.contains(q) || c.code.contains(q.replaceAll('+', '')))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                    hintText: 'ابحث عن دولة',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder()),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final c in list)
                    ListTile(
                      title: Text(c.name),
                      trailing: Text('+${c.code}', textDirection: TextDirection.ltr),
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
