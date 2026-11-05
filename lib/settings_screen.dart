import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'blocked_screen.dart';
import 'profile_setup_screen.dart';
import 'utils.dart';
import 'verify_config.dart';
import 'verify_phone_screen.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  /// true = يُعرض داخل تبويب "أنت" بدون شريط علوي خاص به
  final bool embedded;
  const SettingsScreen({super.key, this.embedded = false});

  Future<void> _deleteAccount(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الحساب نهائياً؟'),
        content: const Text('سيتم حذف حسابك وملفك الشخصي ولا يمكن التراجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final uid = currentUser.uid;
      final userRef = fs.collection('users').doc(uid);
      final phone = ((await userRef.get()).data()?['phone'] ?? '').toString();
      // حذف الملف وتحرير الرقم معاً ليستطيع التسجيل به لاحقاً
      final batch = fs.batch()..delete(userRef);
      if (phone.isNotEmpty) {
        batch.delete(fs.collection('phones').doc(phone.replaceAll('+', '')));
      }
      await batch.commit();
      await currentUser.delete();
      if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      final msg = e.code == 'requires-recent-login'
          ? 'سجّل خروج ثم دخول مرة ثانية وأعد المحاولة'
          : 'تعذر حذف الحساب';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = currentUser;
    final err = Theme.of(context).colorScheme.error;
    final list = ListView(
        children: [
          UserBuilder(
            uid: user.uid,
            builder: (_, u) => ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Avatar(
                  photo: u['photo'] as String?,
                  name: (u['name'] ?? '?').toString(),
                  radius: 32),
              title: Text((u['name'] ?? '').toString(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              subtitle: Text((u['about'] ?? '').toString()),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileSetupScreen(isEdit: true)),
              ),
            ),
          ),
          const Divider(),
          UserBuilder(
            uid: user.uid,
            builder: (_, u) {
              final verified = u['phoneVerified'] == true;
              final pv = phoneValueFromUser(u);
              return ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: const Text('رقم الموبايل'),
                subtitle: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text((u['phone'] ?? '').toString(), textAlign: TextAlign.start)),
                trailing: verified
                    ? const Tooltip(
                        message: 'موثّق',
                        child: Icon(Icons.verified, color: Color(0xFF1DA1F2)))
                    : (pv == null || (kTelegramBot.isEmpty && kWhatsAppNumber.isEmpty)
                        ? null
                        : TextButton(
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => VerifyPhoneScreen(phone: pv))),
                            child: const Text('توثيق'),
                          )),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('حساب Google'),
            subtitle: Text(user.email ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('المحظورون'),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const BlockedScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('عن HaiApp'),
            subtitle: const Text('الإصدار 1.0.0'),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: err),
            title: Text('تسجيل خروج', style: TextStyle(color: err)),
            onTap: () {
              Navigator.popUntil(context, (r) => r.isFirst);
              signOutUser();
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: err),
            title: Text('حذف الحساب', style: TextStyle(color: err)),
            onTap: () => _deleteAccount(context),
          ),
        ],
      );
    if (embedded) return list;
    return Scaffold(appBar: AppBar(title: const Text('الإعدادات')), body: list);
  }
}
