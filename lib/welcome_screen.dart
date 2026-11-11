import 'package:flutter/material.dart';

import 'app_colors.dart';

class WelcomeScreen extends StatelessWidget {
  final VoidCallback onContinue;
  const WelcomeScreen({super.key, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: Image.asset('assets/icon/icon.png', width: 180, height: 180),
              ),
              const SizedBox(height: 32),
              Text('مرحباً بك في HaiChat',
                  style: t.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('تواصل مع أصدقائك وعائلتك بسهولة وخصوصية،\nرسائل وصور ومجموعات وحالات ومكالمات.',
                  textAlign: TextAlign.center, style: t.bodyLarge),
              const Spacer(),
              Text('بالضغط على "الموافقة والمتابعة" فأنت توافق على شروط الاستخدام وسياسة الخصوصية.',
                  textAlign: TextAlign.center, style: t.bodySmall),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: onContinue,
                  child: const Text('الموافقة والمتابعة'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
