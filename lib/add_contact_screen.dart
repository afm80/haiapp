import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'actions.dart';
import 'app_colors.dart';
import 'contacts_service.dart';
import 'phone.dart';

/// صفحة "جهة اتصال جديدة" مثل واتساب: اسم + رقم، وتُحفظ في دفتر هاتفك
class AddContactScreen extends StatefulWidget {
  final String? initialPhone; // بصيغة دولية +964...
  final String? initialName;
  const AddContactScreen({super.key, this.initialPhone, this.initialName});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  late final _name = TextEditingController(text: widget.initialName ?? '');
  late final PhoneValue? _initial =
      widget.initialPhone == null ? null : parseE164(widget.initialPhone!);
  late PhoneValue? _phone = _initial;
  bool _saving = false;

  bool get _ok => _name.text.trim().isNotEmpty && (_phone?.valid ?? false);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    if (!_ok || _saving) return;
    setState(() => _saving = true);
    final phone = _phone!;
    try {
      final granted = await FlutterContacts.requestPermission(readonly: false);
      if (!granted) {
        _snack('اسمح للتطبيق بحفظ جهات الاتصال من إعدادات الجوال');
        return;
      }
      await FlutterContacts.insertContact(Contact(
        name: Name(first: _name.text.trim()),
        phones: [Phone(phone.e164)],
      ));
      await ContactsService.load(force: true);
      final uid = await findUidByPhone(phone);
      if (!mounted) return;
      _snack('تم حفظ جهة الاتصال');
      if (uid != null) {
        openDirectChat(context, uid, _name.text.trim(), replace: true);
      } else {
        await _inviteDialog(phone);
        if (mounted) Navigator.pop(context, true);
      }
    } catch (_) {
      _snack('تعذر حفظ جهة الاتصال');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _inviteDialog(PhoneValue phone) async {
    final invite = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('غير مسجل في HaiApp'),
        content: Text('${_name.text.trim()} ليس لديه HaiApp بعد. هل تريد دعوته؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لاحقاً')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('دعوة')),
        ],
      ),
    );
    if (invite == true) {
      final uri = Uri(scheme: 'sms', path: phone.e164, queryParameters: {
        'body': 'انضم إليّ على HaiApp للمحادثة والمكالمات المجانية!'
      });
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('جهة اتصال جديدة')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: Theme.of(context).dividerColor.withAlpha(60),
              child: Icon(Icons.person, size: 50, color: Theme.of(context).hintColor),
            ),
          ),
          const SizedBox(height: 28),
          Row(children: [
            const Icon(Icons.person_outline, color: AppColors.accent),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _name,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'الاسم'),
              ),
            ),
          ]),
          const SizedBox(height: 22),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Icon(Icons.phone_outlined, color: AppColors.accent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: PhoneInput(
                initial: _initial,
                onChanged: (v) => setState(() => _phone = v),
              ),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _ok ? AppColors.accent : Colors.grey,
        foregroundColor: Colors.white,
        onPressed: _ok ? _save : null,
        icon: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.check),
        label: const Text('حفظ'),
      ),
    );
  }
}
