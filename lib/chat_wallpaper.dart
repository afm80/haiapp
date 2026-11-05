import 'dart:math';

import 'package:flutter/material.dart';

/// خلفية المحادثة: نقوش هادئة مرسومة بالكود (بدون صور) مثل واتساب
class ChatWallpaper extends StatelessWidget {
  final bool dark;
  final Widget child;
  const ChatWallpaper({super.key, required this.dark, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
        child: RepaintBoundary(
          child: CustomPaint(painter: _DoodlePainter(dark)),
        ),
      ),
      child,
    ]);
  }
}

class _DoodlePainter extends CustomPainter {
  final bool dark;
  _DoodlePainter(this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = dark ? const Color(0xFF0B141A) : const Color(0xFFEFE7DD));
    final ink = dark ? const Color(0xFF1B2A32) : const Color(0xFFDDD2C3);
    final p = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final r = Random(7);
    const cell = 62.0;
    for (var y = 0.0; y < size.height + cell; y += cell) {
      for (var x = 0.0; x < size.width + cell; x += cell) {
        final c = Offset(x + 12 + r.nextDouble() * (cell - 24), y + 12 + r.nextDouble() * (cell - 24));
        final a = r.nextDouble() * pi * 2;
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(a);
        switch (r.nextInt(5)) {
          case 0:
            canvas.drawCircle(Offset.zero, 5, p);
            break;
          case 1:
            canvas.drawLine(const Offset(-5, 0), const Offset(5, 0), p);
            canvas.drawLine(const Offset(0, -5), const Offset(0, 5), p);
            break;
          case 2:
            canvas.drawRRect(
                RRect.fromRectAndRadius(
                    const Rect.fromLTWH(-6, -5, 12, 10), const Radius.circular(3)),
                p);
            break;
          case 3:
            final path = Path()
              ..moveTo(0, -6)
              ..lineTo(5, 5)
              ..lineTo(-5, 5)
              ..close();
            canvas.drawPath(path, p);
            break;
          default:
            canvas.drawArc(const Rect.fromLTWH(-6, -6, 12, 12), 0, pi * 1.4, false, p);
        }
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DoodlePainter old) => old.dark != dark;
}
