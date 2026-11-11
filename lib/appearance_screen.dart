import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'chat_wallpaper.dart';
import 'utils.dart';

/// اختيار خلفية المحادثة (محفوظ في حسابك فيتبعك على كل جهاز)
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  Future<void> _pick(String id) async {
    wallpaperPref.value = id;
    try {
      await fs.collection('users').doc(currentUser.uid).update({'wallpaper': id});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('خلفية المحادثة')),
      body: ValueListenableBuilder<String>(
        valueListenable: wallpaperPref,
        builder: (_, current, __) => GridView.count(
          crossAxisCount: 2,
          padding: const EdgeInsets.all(16),
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.8,
          children: [
            for (final e in kWallpapers.entries)
              GestureDetector(
                onTap: () => _pick(e.key),
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: current == e.key ? AppColors.accent : Colors.transparent,
                              width: 3),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: wallpaperColors(e.key, dark),
                          ),
                        ),
                        child: Center(
                          child: e.key == 'flowers'
                              ? Text('🌸 🌷 🌼',
                                  style: TextStyle(fontSize: 22, color: Colors.black.withAlpha(120)))
                              : current == e.key
                                  ? const Icon(Icons.check_circle, color: AppColors.accent, size: 32)
                                  : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(e.value),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
