import 'package:flutter/widgets.dart';
import '../theme/app_theme.dart';
import '../models/audio_models.dart';

enum DeviceType { speaker, headphones, unknown }

class DeviceIcon extends StatelessWidget {
  final AudioDevice? device;
  final String? deviceName;
  final Color? color;
  final double size;

  const DeviceIcon({
    super.key,
    this.device,
    this.deviceName,
    this.color,
    this.size = 14,
  });

  DeviceType get type {
    final name = (deviceName ?? device?.name ?? '').toLowerCase();
    if (name.contains('speaker') || name.contains('enceinte') || name.contains('haut-parleur')) {
      return DeviceType.speaker;
    }
    if (name.contains('headphone') || name.contains('headset') || name.contains('casque') || name.contains('écouteur')) {
      return DeviceType.headphones;
    }
    return DeviceType.speaker; // Default to speaker icon for generic devices
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? AppColors.textTertiary;
    
    return CustomPaint(
      size: Size(size, size),
      painter: type == DeviceType.headphones
          ? _HeadphonePainter(color: iconColor)
          : _SpeakerPainter(color: iconColor),
    );
  }
}

class _SpeakerPainter extends CustomPainter {
  final Color color;
  _SpeakerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // Body of the speaker
    canvas.drawLine(Offset(cx - w * 0.2, cy - h * 0.1), Offset(cx - w * 0.2, cy + h * 0.1), paint);
    canvas.drawLine(Offset(cx - w * 0.2, cy - h * 0.1), Offset(cx + w * 0.05, cy - h * 0.25), paint);
    canvas.drawLine(Offset(cx - w * 0.2, cy + h * 0.1), Offset(cx + w * 0.05, cy + h * 0.25), paint);
    canvas.drawLine(Offset(cx + w * 0.05, cy - h * 0.25), Offset(cx + w * 0.05, cy + h * 0.25), paint);

    // Sound waves
    final wave = Path()
      ..moveTo(cx + w * 0.15, cy - h * 0.15)
      ..quadraticBezierTo(cx + w * 0.3, cy, cx + w * 0.15, cy + h * 0.15);
    canvas.drawPath(wave, paint);
  }

  @override
  bool shouldRepaint(_SpeakerPainter old) => old.color != color;
}

class _HeadphonePainter extends CustomPainter {
  final Color color;
  _HeadphonePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // Headband
    final arcRect = Rect.fromLTWH(w * 0.1, h * 0.1, w * 0.8, h * 0.7);
    canvas.drawArc(arcRect, 3.14, 3.14, false, paint);

    // Ear cups
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.05, h * 0.5, w * 0.3, h * 0.85, const Radius.circular(2)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.7, h * 0.5, w * 0.95, h * 0.85, const Radius.circular(2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_HeadphonePainter old) => old.color != color;
}
