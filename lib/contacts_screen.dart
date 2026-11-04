import 'package:flutter/material.dart';

import 'actions.dart';
import 'app_colors.dart';
import 'contacts_service.dart';
import 'new_group_screen.dart';
import 'widgets.dart';

enum ContactsMode { chat, call }

/// جهات الاتصال المسجلة في التطبيق، تُطابق بالرقم مع دفتر هاتف الجوال (مثل واتساب)
class ContactsScreen extends StatefulWidget {
  final ContactsMode mode;
  const ContactsScreen({super.key, this.mode = ContactsMode.chat});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _search = TextEditingController();
  bool _searching = false;
  String _q = '';
  int _reload = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCall = widget.mode == ContactsMode.call;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                    hintText: 'بحث عن اسم...',
                    hintStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none),
                onChanged: (v) => setState(() => _q = v.trim()),
              )
            : Text(isCall ? 'اختر جهة اتصال' : 'محادثة جديدة'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _search.clear();
              _q = '';
            }),
          ),
          IconButton(
            tooltip: 'تحديث جهات الاتصال',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _reload++),
          ),
        ],
      ),
      body: ContactsView(
        reload: _reload,
        builder: (context, all) {
          final users = all.where((m) => _q.isEmpty || m.name.contains(_q)).toList();
          return ListView(
            children: [
              if (!isCall && _q.isEmpty)
                ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: AppColors.accent,
                      child: Icon(Icons.group_add, color: Colors.white)),
                  title: const Text('مجموعة جديدة'),
                  onTap: () => Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const NewGroupScreen())),
                ),
              if (users.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'ما لقينا أحد من جهات اتصالك مسجلاً في HaiApp بعد.\n'
                      'ادعُ أصدقاءك للتسجيل بأرقامهم.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              for (final m in users)
                ListTile(
                  leading: Avatar(photo: m.user['photo'] as String?, name: m.name, radius: 24),
                  title: Text(m.name),
                  subtitle: Text((m.user['about'] ?? '').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: isCall
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.call, color: AppColors.primary),
                              onPressed: () => startCall(context,
                                  calleeIds: [m.uid], title: m.name, video: false),
                            ),
                            IconButton(
                              icon: const Icon(Icons.videocam, color: AppColors.primary),
                              onPressed: () => startCall(context,
                                  calleeIds: [m.uid], title: m.name, video: true),
                            ),
                          ],
                        )
                      : null,
                  onTap: isCall
                      ? null
                      : () => openDirectChat(context, m.uid, m.name, replace: true),
                ),
            ],
          );
        },
      ),
    );
  }
}
