import 'dart:math';

import 'package:flutter/material.dart';

/// خلفية المحادثة: ورود وشعار التطبيق مرسومة بالكود (بدون صور)
class ChatWallpaper extends StatelessWidget {
  final bool dark;
  final Widget child;
  const ChatWallpaper({super.key, required this.dark, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
        child: RepaintBoundary(
          child: CustomPaint(painter: _PatternPainter(dark)),
        ),
      ),
      child,
    ]);
  }
}

class _PatternPainter extends CustomPainter {
  final bool dark;
  _PatternPainter(this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size,
        Paint()..color = dark ? const Color(0xFF0B141A) : const Color(0xFFEFE7DD));
    final ink = dark ? const Color(0xFF1C2D36) : const Color(0xFFDCD0BF);
    final p = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = ink
      ..style = PaintingStyle.fill;

    const cell = 76.0;
    var row = 0;
    var n = 0;
    for (var y = 20.0; y < size.height + cell; y += cell, row++) {
      final shift = row.isOdd ? cell / 2 : 0.0;
      for (var x = -cell + shift + 20; x < size.width + cell; x += cell, n++) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(((n * 37) % 60 - 30) * pi / 180);
        switch (n % 3) {
          case 0:
            _rose(canvas, p, 13);
            break;
          case 1:
            _logo(canvas, p, fill, 13);
            break;
          default:
            _bud(canvas, p, 8);
        }
        canvas.restore();
      }
    }
  }

  /// وردة: بتلات متداخلة + أوراق
  void _rose(Canvas c, Paint p, double r) {
    // أوراق
    for (final a in [-2.3, -0.8]) {
      final leaf = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(cos(a) * r * 1.0 - sin(a) * r * 0.5, sin(a) * r * 1.0 + cos(a) * r * 0.5,
            cos(a) * r * 1.9, sin(a) * r * 1.9)
        ..quadraticBezierTo(cos(a) * r * 1.0 + sin(a) * r * 0.5, sin(a) * r * 1.0 - cos(a) * r * 0.5,
            0, 0);
      c.drawPath(leaf, p);
    }
    // بتلات خارجية
    for (var i = 0; i < 5; i++) {
      final a = i * 2 * pi / 5;
      c.drawCircle(Offset(cos(a), sin(a)) * r * 0.62, r * 0.5, p);
    }
    // قلب الوردة (لولب)
    final sp = Path();
    for (var t = 0.0; t < 3.5 * pi; t += 0.25) {
      final rr = r * 0.08 + t * r * 0.045;
      final o = Offset(cos(t) * rr, sin(t) * rr);
      if (t == 0) {
        sp.moveTo(o.dx, o.dy);
      } else {
        sp.lineTo(o.dx, o.dy);
      }
    }
    c.drawPath(sp, p);
  }

  /// برعم صغير
  void _bud(Canvas c, Paint p, double r) {
    for (var i = 0; i < 3; i++) {
      final a = -pi / 2 + (i - 1) * 0.7;
      final petal = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(cos(a - 0.5) * r, sin(a - 0.5) * r, cos(a) * r * 1.3, sin(a) * r * 1.3)
        ..quadraticBezierTo(cos(a + 0.5) * r, sin(a + 0.5) * r, 0, 0);
      c.drawPath(petal, p);
    }
    c.drawLine(Offset.zero, Offset(0, r * 1.5), p);
  }

  /// شعار HaiApp: فقاعة محادثة + طائرة ورقية
  void _logo(Canvas c, Paint p, Paint fill, double r) {
    final bubble = Path()
      ..addArc(Rect.fromCircle(center: Offset.zero, radius: r), -pi * 0.18 + pi * 0.0, pi * 1.78 - 0.0);
    // ذيل الفقاعة
    final tail = Path()
      ..moveTo(r * 0.82, r * 0.52)
      ..lineTo(r * 1.35, r * 1.3)
      ..lineTo(r * 0.35, r * 0.95);
    c.drawPath(bubble, p);
    c.drawPath(tail, p);
    // طائرة ورقية
    final plane = Path()
      ..moveTo(-r * 0.45, -r * 0.35)
      ..lineTo(r * 0.5, 0)
      ..lineTo(-r * 0.1, r * 0.1)
      ..lineTo(-r * 0.3, r * 0.45)
      ..close();
    c.drawPath(plane, fill);
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) => old.dark != dark;
}
