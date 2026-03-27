import 'dart:math' show sqrt;
import 'package:fluent_ui/fluent_ui.dart';

/// A smooth, thin audio peak level indicator.
/// No Material widgets used — pure custom paint.
class PeakLevelBar extends StatelessWidget {
  final double level; // 0.0 - 1.0
  final Color color;
  final double width;
  final double height;

  const PeakLevelBar({
    super.key,
    required this.level,
    required this.color,
    this.width = 56,
    this.height = 3,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _PeakPainter(
          level: level,
          color: color,
        ),
      ),
    );
  }
}

class _PeakPainter extends CustomPainter {
  final double level;
  final Color color;

  _PeakPainter({required this.level, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final fgPaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    final radius = Radius.circular(size.height / 2);
    
    // Background track
    canvas.drawRRect(
      RRect.fromLTRBR(0, 0, size.width, size.height, radius),
      bgPaint,
    );

    // Active level — 4th-root curve (double sqrt) + 2× pre-boost for high sensitivity.
    // Example: raw=0.05 → boosted=0.10 → display=0.56 (56 % of bar width).
    //          raw=0.10 → boosted=0.20 → display=0.67
    //          raw=0.30 → boosted=0.60 → display=0.88
    final boosted = (level * 2.0).clamp(0.0, 1.0);
    final displayLevel = sqrt(sqrt(boosted));
    if (displayLevel > 0.02) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, 0, size.width * displayLevel, size.height, radius),
        fgPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_PeakPainter old) =>
      (old.level - level).abs() > 0.001 || old.color != color;
}
