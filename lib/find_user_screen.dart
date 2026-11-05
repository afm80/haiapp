import 'package:flutter/material.dart';

import 'actions.dart';
import 'app_colors.dart';
import 'username.dart';
import 'utils.dart';
import 'widgets.dart';

/// البحث عن مستخدم باسمه الدقيق (@username) وبدء محادثة معه
class FindUserScreen extends StatefulWidget {
  const FindUserScreen({super.key});

  @override
  State<FindUserScreen> createState() => _FindUserScreenState();
}

class _FindUserScreenState extends State<FindUserScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _msg;
  String? _uid;
  Map<String, dynamic>? _user;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final v = _ctrl.text.trim().toLowerCase().replaceAll('@', '');
    setState(() {
      _msg = null;
      _uid = null;
      _user = null;
    });
    if (validateUsername(v) != null) {
      setState(() => _msg = 'اكتب اسم مستخدم صحيح (4 أحرف على الأقل)');
      return;
    }
    setState(() => _busy = true);
    try {
      final n = await fs.collection('usernames').doc(v).get();
      final uid = n.data()?['uid'] as String?;
      if (uid == null) {
        setState(() => _msg = 'لا يوجد مستخدم بهذا الاسم');
      } else if (uid == currentUser.uid) {
        setState(() => _msg = 'هذا اسمك أنت 🙂');
      } else {
        final u = await fs.collection('users').doc(uid).get();
        if (u.data() == null) {
          setState(() => _msg = 'لا يوجد مستخدم بهذا الاسم');
        } else {
          setState(() {
            _uid = uid;
            _user = u.data();
          });
        }
      }
    } catch (_) {
      setState(() => _msg = 'تعذر البحث، تأكد من الاتصال');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    final name = (u?['name'] ?? '').toString();
    return Scaffold(
      appBar: AppBar(title: const Text('بحث باسم المستخدم')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                prefixText: '@',
                hintText: 'username',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _busy ? null : _search),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_msg != null) Center(child: Text(_msg!)),
          if (u != null && _uid != null)
            Card(
              child: ListTile(
                leading: Avatar(photo: u['photo'] as String?, name: name, radius: 26),
                title: Text(name),
                subtitle: Text('@${(u['username'] ?? '').toString()}'),
                trailing: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent, foregroundColor: Colors.white),
                  onPressed: () => openDirectChat(context, _uid!, name, replace: true),
                  child: const Text('مراسلة'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
