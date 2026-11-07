import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// معاينة الصورة قبل الإرسال مع إمكانية كتابة تعليق (مثل واتساب).
/// تُرجع نص التعليق (قد يكون فارغاً) عند الإرسال، أو null عند الإلغاء.
class ImagePreviewScreen extends StatefulWidget {
  final Uint8List bytes;
  final String chatTitle;
  const ImagePreviewScreen({super.key, required this.bytes, required this.chatTitle});

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  final _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(children: [
        Expanded(
          child: Center(
            child: InteractiveViewer(child: Image.memory(widget.bytes, fit: BoxFit.contain)),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                8, 6, 8, 8 + MediaQuery.of(context).viewInsets.bottom * 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2C34),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: TextField(
                    controller: _caption,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: 'أضف تعليقاً...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                      prefixIcon: const Icon(Icons.add_photo_alternate_outlined,
                          color: Colors.white70),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 25,
                backgroundColor: AppColors.accent,
                child: IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.send),
                  onPressed: () => Navigator.pop(context, _caption.text.trim()),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
