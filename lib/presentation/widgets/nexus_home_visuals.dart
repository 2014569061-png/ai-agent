import 'package:flutter/material.dart';

/// Fine, consistent strokes for the phone welcome screen and composer.
enum NexusHomeSymbol { menu, compose, document, project, agent, model }

class NexusHomeIcon extends StatelessWidget {
  const NexusHomeIcon(this.symbol, {super.key, this.size = 22, this.color});
  final NexusHomeSymbol symbol;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
              painter: _HomeIconPainter(symbol,
                  color ?? Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}

class _HomeIconPainter extends CustomPainter {
  const _HomeIconPainter(this.symbol, this.color);
  final NexusHomeSymbol symbol;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x, double y, double endX, double endY) =>
        canvas.drawLine(Offset(x, y), Offset(endX, endY), pen);
    switch (symbol) {
      case NexusHomeSymbol.menu:
        for (final y in [6.5, 12.0, 17.5]) {
          line(4, y, 20, y);
        }
      case NexusHomeSymbol.compose:
        canvas.drawPath(
            Path()
              ..moveTo(12, 4)
              ..lineTo(6, 4)
              ..quadraticBezierTo(4, 4, 4, 6)
              ..lineTo(4, 18)
              ..quadraticBezierTo(4, 20, 6, 20)
              ..lineTo(18, 20)
              ..quadraticBezierTo(20, 20, 20, 18)
              ..lineTo(20, 12),
            pen);
        canvas.drawPath(
            Path()
              ..moveTo(10, 14)
              ..lineTo(10, 17)
              ..lineTo(13, 16)
              ..lineTo(21, 8)
              ..lineTo(18, 5)
              ..close(),
            pen);
        line(16.5, 6.5, 19.5, 9.5);
      case NexusHomeSymbol.document:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(5, 3, 14, 18), const Radius.circular(2)),
            pen);
        line(9, 8, 15, 8);
        line(9, 12, 15, 12);
        line(9, 16, 13, 16);
      case NexusHomeSymbol.project:
        canvas.drawPath(
            Path()
              ..moveTo(4, 8)
              ..lineTo(4, 6)
              ..quadraticBezierTo(4, 4, 6, 4)
              ..lineTo(10, 4)
              ..lineTo(12, 7)
              ..lineTo(18, 7)
              ..quadraticBezierTo(20, 7, 20, 9)
              ..lineTo(20, 18)
              ..quadraticBezierTo(20, 20, 18, 20)
              ..lineTo(6, 20)
              ..quadraticBezierTo(4, 20, 4, 18)
              ..close(),
            pen);
        line(4, 9, 20, 9);
      case NexusHomeSymbol.agent:
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(5, 7, 14, 13), const Radius.circular(4)),
            pen);
        line(12, 4, 12, 7);
        line(9, 12, 9, 12.3);
        line(15, 12, 15, 12.3);
        line(9, 16, 15, 16);
        line(2.5, 11, 2.5, 16);
        line(21.5, 11, 21.5, 16);
      case NexusHomeSymbol.model:
        canvas.drawPath(
            Path()
              ..moveTo(12, 3)
              ..lineTo(20, 7.5)
              ..lineTo(20, 16.5)
              ..lineTo(12, 21)
              ..lineTo(4, 16.5)
              ..lineTo(4, 7.5)
              ..close(),
            pen);
        canvas.drawPath(
            Path()
              ..moveTo(4, 7.5)
              ..lineTo(12, 12)
              ..lineTo(20, 7.5),
            pen);
        line(12, 12, 12, 21);
    }
  }

  @override
  bool shouldRepaint(_HomeIconPainter oldDelegate) =>
      oldDelegate.symbol != symbol || oldDelegate.color != color;
}

/// Only used for the default empty conversation; custom user backgrounds win.
class NexusWelcomeCanvas extends StatelessWidget {
  const NexusWelcomeCanvas({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF111A29), Color(0xFF111722)]
              : const [Colors.white, Color(0xFFFAFCFF)],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -.45),
            radius: .75,
            colors: dark
                ? const [Color(0x143F8BFF), Color(0x003F8BFF)]
                : const [Color(0x1968ADFF), Color(0x0068ADFF)],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
