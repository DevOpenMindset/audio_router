import 'dart:async';
import 'dart:ui' as ui;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';

/// Shows the real process icon extracted from the exe via FFI.
/// Falls back to [AppIconPainter] if extraction fails.
class NativeAppIcon extends StatefulWidget {
  final String processId;
  final String processName;
  final double size;

  const NativeAppIcon({
    super.key,
    required this.processId,
    required this.processName,
    this.size = 34,
  });

  @override
  State<NativeAppIcon> createState() => _NativeAppIconState();
}

class _NativeAppIconState extends State<NativeAppIcon> {
  // Shared cache across all instances: pid → decoded image (null = failed)
  static final Map<String, ui.Image?> _cache = {};

  ui.Image? _image;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // Defer until after first frame so context.read is valid
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadIcon();
    });
  }

  Future<void> _loadIcon() async {
    final pid = widget.processId;
    if (_cache.containsKey(pid)) {
      if (mounted) setState(() { _image = _cache[pid]; _loaded = true; });
      return;
    }

    final bytes = context.read<AudioService>().getAppIconBytes(pid);
    if (bytes == null) {
      _cache[pid] = null;
      if (mounted) setState(() => _loaded = true);
      return;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, 32, 32, ui.PixelFormat.rgba8888, completer.complete);
    final image = await completer.future;
    _cache[pid] = image;
    if (mounted) setState(() { _image = image; _loaded = true; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loaded && _image != null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: RawImage(image: _image, fit: BoxFit.contain),
      );
    }
    return AppIconPainter(processName: widget.processName, size: widget.size);
  }
}

/// Custom painted app icons — no asset files needed.
class AppIconPainter extends StatelessWidget {
  final String processName;
  final double size;

  const AppIconPainter({
    super.key,
    required this.processName,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.getAppColor(processName);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
      ),
      child: CustomPaint(
        painter: _getIconPainter(processName.toLowerCase()),
      ),
    );
  }

  CustomPainter _getIconPainter(String name) {
    if (name.contains('spotify')) return _SpotifyPainter();
    if (name.contains('discord')) return _DiscordPainter();
    if (name.contains('chrome')) return _PlayPainter(); // Generic media icon
    if (name.contains('teams')) return _TeamsPainter();
    if (name.contains('vlc')) return _VLCPainter();
    return _DefaultAppPainter();
  }
}

/// Inactive/muted app icon
class InactiveAppIcon extends StatelessWidget {
  final double size;

  const InactiveAppIcon({super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
      ),
      child: CustomPaint(
        painter: _MutedIconPainter(),
      ),
    );
  }
}

class _SpotifyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Three curved lines
    for (int i = 0; i < 3; i++) {
      final y = cy - 4 + (i * 4.0);
      final spread = 7.0 - (i * 1.5);
      final path = Path()
        ..moveTo(cx - spread, y + 1)
        ..quadraticBezierTo(cx, y - 2, cx + spread, y + 1);
      canvas.drawPath(path, paint..strokeWidth = 1.6 - (i * 0.1));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DiscordPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Two eyes
    canvas.drawCircle(Offset(cx - 3.5, cy), 2, paint);
    canvas.drawCircle(Offset(cx + 3.5, cy), 2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;

    final path = Path()
      ..moveTo(cx - 3, cy - 5)
      ..lineTo(cx + 5, cy)
      ..lineTo(cx - 3, cy + 5)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TeamsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // T letter
    canvas.drawLine(Offset(cx - 4, cy - 4), Offset(cx + 4, cy - 4), paint);
    canvas.drawLine(Offset(cx, cy - 4), Offset(cx, cy + 4), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _VLCPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Traffic cone shape
    final path = Path()
      ..moveTo(cx - 5, cy + 4)
      ..lineTo(cx - 2, cy - 5)
      ..lineTo(cx + 2, cy - 5)
      ..lineTo(cx + 5, cy + 4)
      ..close();

    canvas.drawPath(path, paint);
    // Stripe
    canvas.drawLine(Offset(cx - 3.5, cy), Offset(cx + 3.5, cy), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DefaultAppPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Speaker icon
    canvas.drawLine(Offset(cx - 4, cy - 2), Offset(cx - 4, cy + 2), paint);
    canvas.drawLine(Offset(cx - 4, cy - 2), Offset(cx - 1, cy - 4), paint);
    canvas.drawLine(Offset(cx - 4, cy + 2), Offset(cx - 1, cy + 4), paint);
    
    // Sound waves
    final wavePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final wave1 = Path()
      ..moveTo(cx + 1, cy - 2)
      ..quadraticBezierTo(cx + 3, cy, cx + 1, cy + 2);
    canvas.drawPath(wave1, wavePaint);

    final wave2 = Path()
      ..moveTo(cx + 3, cy - 4)
      ..quadraticBezierTo(cx + 6, cy, cx + 3, cy + 4);
    canvas.drawPath(wave2, wavePaint..color = Colors.white.withValues(alpha: 0.4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MutedIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textTertiary.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Speaker with X
    canvas.drawLine(Offset(cx - 4, cy - 2), Offset(cx - 4, cy + 2), paint);
    canvas.drawLine(Offset(cx - 4, cy - 2), Offset(cx - 1, cy - 4), paint);
    canvas.drawLine(Offset(cx - 4, cy + 2), Offset(cx - 1, cy + 4), paint);

    // X mark
    canvas.drawLine(Offset(cx + 2, cy - 2), Offset(cx + 5, cy + 2), paint);
    canvas.drawLine(Offset(cx + 5, cy - 2), Offset(cx + 2, cy + 2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
