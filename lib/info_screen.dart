import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'actions.dart';
import 'add_members_screen.dart';
import 'app_colors.dart';
import 'utils.dart';
import 'widgets.dart';

class ChatInfoScreen extends StatelessWidget {
  final String chatId;
  const ChatInfoScreen({super.key, required this.chatId});

  DocumentReference<Map<String, dynamic>> get _ref => fs.collection('chats').doc(chatId);

  bool _isAdmin(Map<String, dynamic> d) {
    final uid = currentUser.uid;
    return d['createdBy'] == uid || List<String>.from(d['admins'] ?? const []).contains(uid);
  }

  Future<void> _leave(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مغادرة المجموعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مغادرة')),
        ],
      ),
    );
    if (ok != true) return;
    final uid = currentUser.uid;
    await _ref.update({
      'participants': FieldValue.arrayRemove([uid]),
      'admins': FieldValue.arrayRemove([uid]),
      'names.$uid': FieldValue.delete(),
    });
    if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }

  Future<void> _rename(BuildContext context, String current) async {
    final ctrl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم المجموعة'),
        content: TextField(controller: ctrl, maxLength: 40, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await _ref.update({'groupName': name});
  }

  Future<void> _pickGroupPhoto() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 320, maxHeight: 320, imageQuality: 70);
    if (x == null) return;
    await _ref.update({'groupPhoto': base64Encode(await x.readAsBytes())});
  }

  void _memberMenu(BuildContext context, String m, Map<String, dynamic> d) {
    final isAdminM = List<String>.from(d['admins'] ?? const []).contains(m);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text(isAdminM ? 'إزالة الإشراف' : 'ترقية إلى مشرف'),
              onTap: () {
                Navigator.pop(ctx);
                _ref.update({
                  'admins': isAdminM
                      ? FieldValue.arrayRemove([m])
                      : FieldValue.arrayUnion([m])
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.person_remove_outlined,
                  color: Theme.of(context).colorScheme.error),
              title: const Text('إزالة من المجموعة'),
              onTap: () {
                Navigator.pop(ctx);
                _ref.update({
                  'participants': FieldValue.arrayRemove([m]),
                  'admins': FieldValue.arrayRemove([m]),
                  'names.$m': FieldValue.delete(),
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('معلومات')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _ref.snapshots(),
        builder: (context, snap) {
          final d = snap.data?.data();
          if (d == null) return const Center(child: CircularProgressIndicator());
          final participants = List<String>.from(d['participants'] ?? const []);
          if (d['isGroup'] == true) return _group(context, d, participants);
          final otherId = participants.firstWhere((p) => p != currentUser.uid,
              orElse: () => currentUser.uid);
          return _direct(context, otherId);
        },
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) => Column(
        children: [
          IconButton.filledTonal(onPressed: onTap, icon: Icon(icon, color: AppColors.primary)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );

  Widget _direct(BuildContext context, String otherId) {
    return UserBuilder(
      uid: otherId,
      builder: (context, u) {
        final name = (u['name'] ?? '').toString();
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(child: Avatar(photo: u['photo'] as String?, name: name, radius: 64)),
            const SizedBox(height: 16),
            Center(child: Text(name, style: Theme.of(context).textTheme.headlineSmall)),
            Center(child: Text(presenceText(u))),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _action(Icons.call, 'صوتية',
                    () => startCall(context, calleeIds: [otherId], title: name, video: false)),
                const SizedBox(width: 24),
                _action(Icons.videocam, 'فيديو',
                    () => startCall(context, calleeIds: [otherId], title: name, video: true)),
              ],
            ),
            const Divider(height: 40),
            const Text('النبذة', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text((u['about'] ?? '').toString()),
            const Divider(height: 40),
            UserBuilder(
              uid: currentUser.uid,
              builder: (_, me) {
                final blocked =
                    List<String>.from(me['blocked'] ?? const []).contains(otherId);
                final err = Theme.of(context).colorScheme.error;
                return ListTile(
                  leading: Icon(Icons.block, color: err),
                  title: Text(blocked ? 'إلغاء حظر $name' : 'حظر $name',
                      style: TextStyle(color: err)),
                  onTap: () => fs.collection('users').doc(currentUser.uid).update({
                    'blocked': blocked
                        ? FieldValue.arrayRemove([otherId])
                        : FieldValue.arrayUnion([otherId])
                  }),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _group(BuildContext context, Map<String, dynamic> d, List<String> members) {
    final title = (d['groupName'] ?? 'مجموعة').toString();
    final admin = _isAdmin(d);
    final err = Theme.of(context).colorScheme.error;
    return ListView(
      children: [
        const SizedBox(height: 24),
        Center(
          child: GestureDetector(
            onTap: admin ? _pickGroupPhoto : null,
            child: Stack(
              children: [
                Avatar(photo: d['groupPhoto'] as String?, name: title, isGroup: true, radius: 64),
                if (admin)
                  const Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.accent,
                      child: Icon(Icons.camera_alt, size: 18, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (admin)
              IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _rename(context, title)),
          ],
        ),
        Center(child: Text('${members.length} أعضاء')),
        const Divider(height: 32),
        if (admin)
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: AppColors.accent,
                child: Icon(Icons.person_add, color: Colors.white)),
            title: const Text('إضافة أعضاء'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AddMembersScreen(chatId: chatId, existing: members)),
            ),
          ),
        for (final m in members)
          UserBuilder(
            uid: m,
            builder: (_, u) {
              final isAdminM = m == d['createdBy'] ||
                  List<String>.from(d['admins'] ?? const []).contains(m);
              return ListTile(
                leading: Avatar(photo: u['photo'] as String?, name: (u['name'] ?? '?').toString()),
                title: Text(m == currentUser.uid ? 'أنت' : (u['name'] ?? '').toString()),
                subtitle: Text((u['about'] ?? '').toString(), maxLines: 1),
                trailing: isAdminM ? const Chip(label: Text('مشرف')) : null,
                onTap: (admin && m != currentUser.uid && m != d['createdBy'])
                    ? () => _memberMenu(context, m, d)
                    : null,
              );
            },
          ),
        const Divider(),
        ListTile(
          leading: Icon(Icons.exit_to_app, color: err),
          title: Text('مغادرة المجموعة', style: TextStyle(color: err)),
          onTap: () => _leave(context),
        ),
      ],
    );
  }
}
