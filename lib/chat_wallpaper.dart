import 'dart:math';

import 'package:flutter/material.dart';

/// خلفية المحادثة: زهور وورود متنوعة مرسومة بالكود (بدون صور)
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

    const cell = 76.0;
    var row = 0;
    var n = 0;
    for (var y = 20.0; y < size.height + cell; y += cell, row++) {
      final shift = row.isOdd ? cell / 2 : 0.0;
      for (var x = -cell + shift + 20; x < size.width + cell; x += cell, n++) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(((n * 37) % 60 - 30) * pi / 180);
        switch (n % 6) {
          case 0:
            _rose(canvas, p, 13);
            break;
          case 1:
            _daisy(canvas, p, 12);
            break;
          case 2:
            _tulip(canvas, p, 12);
            break;
          case 3:
            _blossom(canvas, p, 12);
            break;
          case 4:
            _bud(canvas, p, 9);
            break;
          default:
            _sprig(canvas, p, 14);
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

  /// أقحوان: بتلات طويلة حول قلب
  void _daisy(Canvas c, Paint p, double r) {
    for (var i = 0; i < 10; i++) {
      final a = i * 2 * pi / 10;
      c.save();
      c.rotate(a);
      c.drawOval(Rect.fromCenter(center: Offset(0, -r * 0.95), width: r * 0.55, height: r * 0.95), p);
      c.restore();
    }
    c.drawCircle(Offset.zero, r * 0.32, p);
  }

  /// توليب
  void _tulip(Canvas c, Paint p, double r) {
    final cup = Path()
      ..moveTo(-r * 0.7, -r * 0.9)
      ..quadraticBezierTo(-r * 0.8, r * 0.3, 0, r * 0.45)
      ..quadraticBezierTo(r * 0.8, r * 0.3, r * 0.7, -r * 0.9)
      ..lineTo(r * 0.3, -r * 0.35)
      ..lineTo(0, -r * 1.05)
      ..lineTo(-r * 0.3, -r * 0.35)
      ..close();
    c.drawPath(cup, p);
    c.drawLine(Offset(0, r * 0.45), Offset(0, r * 1.6), p);
    final leaf = Path()
      ..moveTo(0, r * 1.4)
      ..quadraticBezierTo(r * 0.9, r * 1.2, r * 0.8, r * 0.6)
      ..quadraticBezierTo(r * 0.2, r * 0.9, 0, r * 1.4);
    c.drawPath(leaf, p);
  }

  /// زهرة خماسية مدوّرة البتلات (مثل زهر الكرز)
  void _blossom(Canvas c, Paint p, double r) {
    for (var i = 0; i < 5; i++) {
      final a = -pi / 2 + i * 2 * pi / 5;
      final tip = Offset(cos(a), sin(a)) * r;
      final l = Offset(cos(a - 0.45), sin(a - 0.45)) * r * 0.75;
      final rr = Offset(cos(a + 0.45), sin(a + 0.45)) * r * 0.75;
      final petal = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(l.dx, l.dy, tip.dx * 0.95, tip.dy * 0.95)
        ..quadraticBezierTo(rr.dx, rr.dy, 0, 0);
      c.drawPath(petal, p);
    }
    c.drawCircle(Offset.zero, r * 0.14, p);
  }

  /// غصن بأوراق
  void _sprig(Canvas c, Paint p, double r) {
    c.drawLine(Offset(0, r), Offset(0, -r), p);
    for (var i = 0; i < 3; i++) {
      final y = r * 0.6 - i * r * 0.6;
      for (final dir in [-1.0, 1.0]) {
        final leaf = Path()
          ..moveTo(0, y)
          ..quadraticBezierTo(dir * r * 0.7, y - r * 0.15, dir * r * 0.75, y - r * 0.55)
          ..quadraticBezierTo(dir * r * 0.15, y - r * 0.45, 0, y);
        c.drawPath(leaf, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) => old.dark != dark;
}
