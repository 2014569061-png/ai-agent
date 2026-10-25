import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Code-drawn, lightweight light-orbit mark for the mobile welcome screen.
class NexusAssistantEmblem extends StatelessWidget {
  const NexusAssistantEmblem({super.key, this.size = 112});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'NEXUS 助手',
        image: true,
        child: SizedBox(
          width: size * 1.8,
          height: size * 1.65,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(colors: [
                Color(0x224A97FF),
                Color(0x0C4A97FF),
                Color(0x004A97FF),
              ], stops: [
                0,
                .45,
                1
              ]),
            ),
            child: Center(
                child: CustomPaint(
              size: Size.square(size),
              painter: const _OrbitPainter(),
            )),
          ),
        ),
      );
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final unit = size.width;
    final core = Rect.fromCircle(center: center, radius: unit * .30);
    final ellipse = Rect.fromCenter(
        center: Offset.zero, width: unit * .96, height: unit * .44);
    final angles = [-math.pi / 4.1, math.pi / 4.1];
    void ribbon(double angle, bool front) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      canvas.drawArc(
        ellipse,
        front ? 0 : math.pi,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * .075
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: front
                ? const [
                    Color(0xF5FFFFFF),
                    Color(0xE2E9F6FF),
                    Color(0x9198C5FF)
                  ]
                : const [
                    Color(0x60ADCDFF),
                    Color(0xA8DDEFFF),
                    Color(0x407AB5FF)
                  ],
          ).createShader(ellipse),
      );
      canvas.restore();
    }

    for (final angle in angles) {
      ribbon(angle, false);
    }
    canvas.drawCircle(
        center,
        unit * .30,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-.45, -.6),
            radius: 1.2,
            colors: [Color(0xFFEDF9FF), Color(0xFFA3D6FF), Color(0xFF86ABF3)],
          ).createShader(core));
    canvas.drawCircle(
        center,
        unit * .30,
        Paint()
          ..color = const Color(0x6AFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * .012);
    for (final angle in angles) {
      ribbon(angle, true);
    }
    final spark = Path()
      ..moveTo(center.dx, center.dy - unit * .075)
      ..quadraticBezierTo(center.dx + unit * .02, center.dy - unit * .02,
          center.dx + unit * .075, center.dy)
      ..quadraticBezierTo(center.dx + unit * .02, center.dy + unit * .02,
          center.dx, center.dy + unit * .075)
      ..quadraticBezierTo(center.dx - unit * .02, center.dy + unit * .02,
          center.dx - unit * .075, center.dy)
      ..quadraticBezierTo(center.dx - unit * .02, center.dy - unit * .02,
          center.dx, center.dy - unit * .075);
    canvas.drawPath(
        spark, Paint()..color = Colors.white.withValues(alpha: .95));
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) => false;
}
