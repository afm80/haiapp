import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'utils.dart';

/// مستخدم مسجل في التطبيق ورقمه موجود في جهات اتصال الجوال
class ContactMatch {
  final String uid;
  final String contactName; // الاسم المحفوظ في جوال المستخدم
  final Map<String, dynamic> user; // ملفه الشخصي
  const ContactMatch(this.uid, this.contactName, this.user);

  String get name {
    if (contactName.trim().isNotEmpty) return contactName.trim();
    return (user['name'] ?? '').toString();
  }
}

class ContactsResult {
  final bool granted;
  final List<ContactMatch> matches;
  const ContactsResult(this.granted, this.matches);
}

/// الاسم الذي يُعرض للمستخدم مثل واتساب:
/// اسمه في دفتر هاتفك، وإن لم يكن محفوظاً يظهر رقمه، وإن لم تُمنح صلاحية الجهات يظهر اسم ملفه.
String displayNameOf(String uid, Map<String, dynamic> u, Map<String, String>? names) {
  final profile = (u['name'] ?? '').toString();
  if (names == null) return profile;
  final saved = names[uid];
  if (saved != null && saved.isNotEmpty) return saved;
  final phone = (u['phone'] ?? '').toString();
  return phone.isNotEmpty ? '\u200E$phone' : profile;
}

class ContactsService {
  static ContactsResult? _cache;
  static String? _cacheUid;

  /// uid ← اسم الجهة في دفتر الهاتف. null = لم تُمنح صلاحية الجهات (يُعرض اسم الملف الشخصي).
  static final ValueNotifier<Map<String, String>?> names = ValueNotifier(null);

  static Future<ContactsResult> load({bool force = false}) async {
    final me = currentUser.uid;
    if (!force && _cache != null && _cacheUid == me) return _cache!;

    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      names.value = null;
      return const ContactsResult(false, []);
    }

    // رمز دولة المستخدم لإكمال الأرقام المحلية (0770... ← +964770...)
    final meDoc = await fs.collection('users').doc(me).get();
    final myDial = (meDoc.data()?['phoneCountry'] ?? '').toString();
    final myKey = phoneKeyOf(meDoc.data()?['phone']);

    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final keyToName = <String, String>{};
    for (final c in contacts) {
      for (final p in c.phones) {
        for (final k in _candidates(p.number, myDial)) {
          if (k == myKey) continue;
          keyToName.putIfAbsent(k, () => c.displayName);
        }
      }
    }

    // مفتاح الرقم ← uid
    final keyToUid = <String, String>{};
    final keys = keyToName.keys.toList();
    for (var i = 0; i < keys.length; i += 200) {
      final batch = keys.skip(i).take(200).toList();
      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
      for (var j = 0; j < batch.length; j += 10) {
        futures.add(fs
            .collection('phones')
            .where(FieldPath.documentId, whereIn: batch.skip(j).take(10).toList())
            .limit(10) // تشترطه قواعد الأمان لمنع سحب كل الأرقام
            .get());
      }
      for (final snap in await Future.wait(futures)) {
        for (final d in snap.docs) {
          final uid = d.data()['uid'] as String?;
          if (uid != null && uid != me) keyToUid[d.id] = uid;
        }
      }
    }

    // uid ← اسم الجهة (أول مفتاح مطابق)
    final uidToContactName = <String, String>{};
    keyToUid.forEach((k, uid) => uidToContactName.putIfAbsent(uid, () => keyToName[k] ?? ''));

    final uids = uidToContactName.keys.toList();
    final matches = <ContactMatch>[];
    for (var i = 0; i < uids.length; i += 10) {
      final snap = await fs
          .collection('users')
          .where(FieldPath.documentId, whereIn: uids.skip(i).take(10).toList())
          .limit(10)
          .get();
      for (final d in snap.docs) {
        final data = d.data();
        if ((data['name'] ?? '').toString().trim().isEmpty) continue;
        matches.add(ContactMatch(d.id, uidToContactName[d.id] ?? '', data));
      }
    }
    matches.sort((a, b) => a.name.compareTo(b.name));

    _cache = ContactsResult(true, matches);
    _cacheUid = me;
    names.value = {
      for (final m in matches)
        if (m.contactName.trim().isNotEmpty) m.uid: m.contactName.trim()
    };
    return _cache!;
  }

  static void clear() {
    _cache = null;
    _cacheUid = null;
    names.value = null;
  }

  static String phoneKeyOf(dynamic phone) =>
      (phone ?? '').toString().replaceAll('+', '');

  /// الصيغ المحتملة للرقم بعد توحيده (مفتاح = رمز الدولة + الرقم)
  static Set<String> _candidates(String raw, String myDial) {
    final s = latinDigitsLocal(raw.trim());
    final hasPlus = s.startsWith('+');
    final digits = s.replaceAll(RegExp(r'\D'), '');
    final out = <String>{};
    if (digits.isEmpty) return out;
    if (hasPlus) {
      out.add(digits);
    } else if (digits.startsWith('00')) {
      out.add(digits.substring(2));
    } else {
      final national = digits.replaceFirst(RegExp(r'^0+'), '');
      if (myDial.isNotEmpty && national.isNotEmpty) out.add('$myDial$national');
      if (digits.length >= 10) out.add(digits); // مكتوب بالرمز الدولي بدون +
    }
    return out.where((k) => k.length >= 7 && k.length <= 15).toSet();
  }

  static String latinDigitsLocal(String s) {
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
}

/// يعرض جهات الاتصال المسجلة مع حالات التحميل والرفض والفراغ
class ContactsView extends StatefulWidget {
  final Widget Function(BuildContext, List<ContactMatch>) builder;
  final int reload;
  const ContactsView({super.key, required this.builder, this.reload = 0});

  @override
  State<ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends State<ContactsView> {
  late Future<ContactsResult> _future = ContactsService.load();

  @override
  void didUpdateWidget(covariant ContactsView old) {
    super.didUpdateWidget(old);
    if (old.reload != widget.reload) {
      _future = ContactsService.load(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ContactsResult>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _Message(
            icon: Icons.error_outline,
            text: 'تعذر تحميل جهات الاتصال، تأكد من اتصالك بالإنترنت',
            button: 'إعادة المحاولة',
            onPressed: () => setState(() => _future = ContactsService.load(force: true)),
          );
        }
        final r = snap.data!;
        if (!r.granted) {
          return _Message(
            icon: Icons.contacts_outlined,
            text: 'اسمح للتطبيق بالوصول إلى جهات الاتصال لتظهر لك أرقام أصدقائك المسجلين.\n'
                'إن كان الإذن محظوراً فعّله من إعدادات الجوال.',
            button: 'السماح',
            onPressed: () => setState(() => _future = ContactsService.load(force: true)),
          );
        }
        return widget.builder(context, r.matches);
      },
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final String button;
  final VoidCallback onPressed;
  const _Message(
      {required this.icon, required this.text, required this.button, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onPressed, child: Text(button)),
          ],
        ),
      ),
    );
  }
}
