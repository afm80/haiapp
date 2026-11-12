import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

  Future<void> _fromDevice(BuildContext context) async {
    final m = ScaffoldMessenger.of(context);
    try {
      final x = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1280, maxHeight: 1280, imageQuality: 75);
      if (x == null) return;
      await saveCustomWallpaper(await x.readAsBytes());
      await _pick('custom');
      m.showSnackBar(const SnackBar(content: Text('تم تغيير الخلفية')));
    } catch (_) {
      m.showSnackBar(const SnackBar(content: Text('تعذر اختيار الصورة')));
    }
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
            ValueListenableBuilder<String?>(
              valueListenable: customWallpaperPath,
              builder: (context, path, _) => GestureDetector(
                onTap: () => _fromDevice(context),
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.black12,
                          border: Border.all(
                              color: current == 'custom' ? AppColors.accent : Colors.transparent,
                              width: 3),
                          image: (path != null && File(path).existsSync())
                              ? DecorationImage(image: FileImage(File(path)), fit: BoxFit.cover)
                              : null,
                        ),
                        child: Center(
                          child: Icon(Icons.add_photo_alternate_outlined,
                              size: 36,
                              color: (path != null && File(path).existsSync())
                                  ? Colors.white
                                  : Theme.of(context).hintColor),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('من جهازك'),
                  ],
                ),
              ),
            ),
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
