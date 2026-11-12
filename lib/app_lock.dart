import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'app_colors.dart';
import 'app_prefs.dart';
import 'utils.dart';

final LocalAuthentication _auth = LocalAuthentication();

/// هل الجهاز يدعم القفل (بصمة أو رمز/نمط الجهاز)؟
Future<bool> lockSupported() async {
  try {
    return await _auth.isDeviceSupported();
  } catch (_) {
    return false;
  }
}

/// يطلب بصمة الإصبع أو رمز الجهاز
Future<bool> authenticateUser(String reason) async {
  try {
    return await _auth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
    );
  } catch (_) {
    return false;
  }
}

/// شاشة القفل: تغطي التطبيق حتى يتحقق المستخدم
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _try());
  }

  Future<void> _try() async {
    if (_busy) return;
    _busy = true;
    final ok = await authenticateUser('افتح HaiChat');
    _busy = false;
    if (ok && mounted) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset('assets/icon/icon.png', width: 100, height: 100),
              ),
              const SizedBox(height: 20),
              const Text('التطبيق مقفل',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent, foregroundColor: Colors.white),
                onPressed: _try,
                icon: const Icon(Icons.fingerprint),
                label: const Text('فتح القفل'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// خيار قفل التطبيق في الإعدادات
class AppLockTile extends StatefulWidget {
  const AppLockTile({super.key});

  @override
  State<AppLockTile> createState() => _AppLockTileState();
}

class _AppLockTileState extends State<AppLockTile> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    fs.collection('users').doc(currentUser.uid).get().then((d) {
      if (mounted) setState(() => _on = d.data()?['appLock'] == true);
    }, onError: (_) {});
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _toggle(bool v) async {
    if (!await lockSupported()) {
      _snack('جهازك لا يدعم القفل. فعّل بصمة أو رمز قفل للشاشة من إعدادات الجهاز أولاً');
      return;
    }
    final ok = await authenticateUser(v ? 'أكّد هويتك لتفعيل القفل' : 'أكّد هويتك لإيقاف القفل');
    if (!ok) return;
    try {
      await fs.collection('users').doc(currentUser.uid).update({'appLock': v});
      if (mounted) setState(() => _on = v);
    } catch (_) {
      _snack('تعذر الحفظ، حاول مرة أخرى');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint),
      title: const Text('قفل التطبيق'),
      subtitle: const Text('بصمة الإصبع أو رمز الجهاز عند فتح التطبيق'),
      value: _on,
      activeColor: AppColors.accent,
      onChanged: _toggle,
    );
  }
}

/// خيار المظهر: تلقائي / فاتح / داكن
class ThemeModeTile extends StatelessWidget {
  const ThemeModeTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModePref,
      builder: (context, mode, _) => ListTile(
        leading: const Icon(Icons.brightness_6_outlined),
        title: const Text('المظهر'),
        subtitle: Text(mode == ThemeMode.light
            ? 'فاتح'
            : (mode == ThemeMode.dark ? 'داكن' : 'تلقائي (حسب الجهاز)')),
        onTap: () async {
          final picked = await showDialog<ThemeMode>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('المظهر'),
              children: [
                for (final e in const {
                  ThemeMode.system: 'تلقائي (حسب الجهاز)',
                  ThemeMode.light: 'فاتح',
                  ThemeMode.dark: 'داكن',
                }.entries)
                  RadioListTile<ThemeMode>(
                    value: e.key,
                    groupValue: mode,
                    activeColor: AppColors.accent,
                    title: Text(e.value),
                    onChanged: (v) => Navigator.pop(ctx, v),
                  ),
              ],
            ),
          );
          if (picked == null) return;
          themeModePref.value = picked;
          try {
            await fs
                .collection('users')
                .doc(currentUser.uid)
                .update({'themeMode': themeModeToString(picked)});
          } catch (_) {}
        },
      ),
    );
  }
}
