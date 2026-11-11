import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'contacts_service.dart';
import 'utils.dart';

/// من يرى حالتي: جهات اتصالي / جهات اتصالي ما عدا... / مشاركة مع... فقط
class StatusPrivacyScreen extends StatefulWidget {
  const StatusPrivacyScreen({super.key});

  @override
  State<StatusPrivacyScreen> createState() => _StatusPrivacyScreenState();
}

class _StatusPrivacyScreenState extends State<StatusPrivacyScreen> {
  String _mode = 'all';
  final Set<String> _list = {};
  List<ContactMatch> _contacts = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await fs.collection('users').doc(currentUser.uid).get();
      final p = d.data()?['statusPrivacy'];
      if (p is Map) {
        final m = (p['mode'] ?? 'all').toString();
        if (const ['all', 'except', 'only'].contains(m)) _mode = m;
        _list.addAll(List<String>.from(p['list'] ?? const []));
      }
    } catch (_) {}
    try {
      final res = await ContactsService.load();
      _contacts = res.matches;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await fs.collection('users').doc(currentUser.uid).update({
        'statusPrivacy': {'mode': _mode, 'list': _mode == 'all' ? <String>[] : _list.toList()},
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم حفظ خصوصية الحالة')));
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر الحفظ، حاول مرة أخرى')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget mode(String id, String title, String sub) => RadioListTile<String>(
          value: id,
          groupValue: _mode,
          activeColor: AppColors.accent,
          title: Text(title),
          subtitle: Text(sub),
          onChanged: (v) => setState(() => _mode = v ?? 'all'),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('خصوصية الحالة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('من يستطيع رؤية حالتي؟ يسري التغيير على الحالات الجديدة فقط.'),
                ),
                mode('all', 'جهات اتصالي', 'كل من في جهات اتصالك ويستخدم التطبيق'),
                mode('except', 'جهات اتصالي ما عدا...', 'تختار من لا يرى حالتك'),
                mode('only', 'مشاركة مع... فقط', 'تختار من يرى حالتك'),
                if (_mode != 'all') ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      _mode == 'except' ? 'اختر من تخفي عنهم حالتك:' : 'اختر من يرى حالتك:',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (_contacts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('لا توجد جهات اتصال تستخدم التطبيق، أو لم تسمح بالوصول للجهات.'),
                    ),
                  for (final c in _contacts)
                    CheckboxListTile(
                      value: _list.contains(c.uid),
                      activeColor: AppColors.accent,
                      title: Text(c.contactName.isNotEmpty
                          ? c.contactName
                          : (c.user['name'] ?? '').toString()),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _list.add(c.uid);
                        } else {
                          _list.remove(c.uid);
                        }
                      }),
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('حفظ'),
                  ),
                ),
              ],
            ),
    );
  }
}
