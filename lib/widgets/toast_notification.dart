import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/theme_service.dart';
import '../l10n/app_localizations.dart';

/// Lightweight toast overlay — works on Windows and macOS.
/// Usage:
///   AudioToast.showConnected(context, 'Casque HyperX');
///   AudioToast.showDisconnected(context, 'Galaxy Buds');
class AudioToast {
  AudioToast._();

  static OverlayEntry? _current;
  static Timer? _timer;

  static void showConnected(BuildContext context, String deviceName) {
    final locale = context.read<ThemeService>().locale;
    final l10n = AppLocalizations(locale);
    _show(
      context,
      icon: '🔌',
      message: '$deviceName ${l10n.connected}',
      accent: const Color(0xFF1A6B3C),
      border: const Color(0xFF2E9E5B),
    );
  }

  static void showDisconnected(BuildContext context, String deviceName) {
    final locale = context.read<ThemeService>().locale;
    final l10n = AppLocalizations(locale);
    _show(
      context,
      icon: '🔇',
      message: '$deviceName ${l10n.disconnected}',
      accent: const Color(0xFF6B2020),
      border: const Color(0xFF9E3030),
    );
  }

  static void _show(
    BuildContext context, {
    required String icon,
    required String message,
    required Color accent,
    required Color border,
  }) {
    _timer?.cancel();
    _current?.remove();
    _current = null;

    final overlay = Overlay.of(context, rootOverlay: true);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        icon: icon,
        message: message,
        accent: accent,
        border: border,
        onDismiss: () {
          entry.remove();
          if (_current == entry) _current = null;
        },
      ),
    );

    _current = entry;
    overlay.insert(entry);

    _timer = Timer(const Duration(seconds: 3), () {
      entry.remove();
      if (_current == entry) _current = null;
    });
  }
}

class _ToastWidget extends StatefulWidget {
  final String icon;
  final String message;
  final Color accent;
  final Color border;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.icon,
    required this.message,
    required this.accent,
    required this.border,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: SlideTransition(
            position: _slide,
            child: GestureDetector(
              onTap: widget.onDismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(AppColors.cardRadius),
                  border: Border.all(color: widget.border, width: 0.8),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accent.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.icon,
                        style: const TextStyle(fontSize: 14, height: 1.2)),
                    const SizedBox(width: 8),
                    Text(
                      widget.message,
                      style: AppTheme.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFFFFFFF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
