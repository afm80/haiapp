import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// حفظ الصورة في معرض الجوال
Future<bool> saveImageToGallery(BuildContext context, Uint8List bytes) async {
  final m = ScaffoldMessenger.of(context);
  try {
    await Gal.putImageBytes(bytes, album: 'HaiApp');
    m.showSnackBar(const SnackBar(content: Text('تم حفظ الصورة في المعرض')));
    return true;
  } catch (_) {
    m.showSnackBar(const SnackBar(content: Text('تعذر حفظ الصورة، تأكد من السماح بالوصول للصور')));
    return false;
  }
}

/// مشاركة الصورة لتطبيقات أخرى
Future<void> shareImage(BuildContext context, Uint8List bytes) async {
  final m = ScaffoldMessenger.of(context);
  try {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/HaiApp_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await f.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(f.path)]);
  } catch (_) {
    m.showSnackBar(const SnackBar(content: Text('تعذرت المشاركة')));
  }
}

/// عرض الصورة كاملة مع حفظ ومشاركة
class ImageViewerScreen extends StatelessWidget {
  final Uint8List bytes;
  const ImageViewerScreen({super.key, required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'حفظ',
            icon: const Icon(Icons.download),
            onPressed: () => saveImageToGallery(context, bytes),
          ),
          IconButton(
            tooltip: 'مشاركة',
            icon: const Icon(Icons.share),
            onPressed: () => shareImage(context, bytes),
          ),
        ],
      ),
      body: Center(child: InteractiveViewer(child: Image.memory(bytes))),
    );
  }
}
