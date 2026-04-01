import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:fluent_ui/fluent_ui.dart' hide Color, Offset, FontWeight, Brightness, TextStyle, BoxShadow;
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';

class NativeAppIcon extends StatefulWidget {
  final String processId;
  final String processName;
  final double size;

  const NativeAppIcon({
    super.key,
    required this.processId,
    required this.processName,
    this.size = 32,
  });

  @override
  State<NativeAppIcon> createState() => _NativeAppIconState();
}

class _NativeAppIconState extends State<NativeAppIcon> {
  ui.Image? _image;
  bool _loaded = false;

  static final Map<String, ui.Image?> _cache = {};

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  @override
  void didUpdateWidget(NativeAppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.processId != widget.processId) {
      _loadIcon();
    }
  }

  Future<void> _loadIcon() async {
    final pid = widget.processId;
    if (_cache.containsKey(pid)) {
      if (mounted) {
        setState(() {
          _image = _cache[pid];
          _loaded = true;
        });
      }
      return;
    }

    final bytes = context.read<AudioService>().getAppIconBytes(pid);
    if (bytes == null) {
      _cache[pid] = null;
      if (mounted) setState(() => _loaded = true);
      return;
    }

    // Extract dominant color before decoding image (Full Dart)
    final dominantColor = _extractDominantColor(bytes);
    if (dominantColor != null) {
      AppColors.setDynamicColor(pid, dominantColor);
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, 32, 32, ui.PixelFormat.rgba8888, (image) {
      completer.complete(image);
    });
    
    final image = await completer.future;
    _cache[pid] = image;
    if (mounted) {
      setState(() {
        _image = image;
        _loaded = true;
      });
    }
  }

  ui.Color? _extractDominantColor(Uint8List bytes) {
    if (bytes.length < 4096) return null; // 32x32x4
    
    int r = 0, g = 0, b = 0, count = 0;
    
    for (int i = 0; i < bytes.length; i += 4) {
      final alpha = bytes[i + 3];
      if (alpha < 180) continue; // Skip semi-transparent / transparent

      final int pr = bytes[i];
      final int pg = bytes[i + 1];
      final int pb = bytes[i + 2];

      // Skip near-white and near-black to get better brand colors
      final double brightness = (pr + pg + pb) / 3.0;
      if (brightness > 240 || brightness < 20) continue;

      r += pr;
      g += pg;
      b += pb;
      count++;
    }

    if (count == 0) return null;
    
    return ui.Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
  }

  @override
  Widget build(BuildContext context) {
    if (_loaded && _image != null) {
      return RawImage(
        image: _image,
        width: widget.size,
        height: widget.size,
        filterQuality: FilterQuality.medium,
      );
    }
    return InactiveAppIcon(size: widget.size);
  }
}

class InactiveAppIcon extends StatelessWidget {
  final double size;
  const InactiveAppIcon({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Icon(
      FluentIcons.error_badge,
      size: size,
      color: AppColors.textTertiary.withValues(alpha: 0.4),
    );
  }
}
