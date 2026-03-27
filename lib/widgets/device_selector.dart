import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'adaptive_widgets.dart';
import '../theme/app_theme.dart';
import '../models/audio_models.dart';
import '../platform.dart';
import '../services/theme_service.dart';
import '../l10n/app_localizations.dart';

/// Fluent ComboBox device selector.
class DeviceSelector extends StatelessWidget {
  final AudioDevice? selectedDevice;
  final List<AudioDevice> devices;
  final ValueChanged<AudioDevice> onChanged;

  const DeviceSelector({
    super.key,
    required this.selectedDevice,
    required this.devices,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final l10n = context.l10n;
    final activeDevices = devices.where((d) => d.isActive).toList();
    // When no explicit route, fall back to showing the default device
    final effectiveDevice = selectedDevice ??
        activeDevices.where((d) => d.isDefault).firstOrNull ??
        (activeDevices.isNotEmpty ? activeDevices.first : null);
    return AdaptiveComboBox<AudioDevice>(
      value: effectiveDevice,
      isExpanded: true,
      style: AppTheme.inter(fontSize: 12, color: AppColors.textSecondary),
      items: activeDevices.map((device) => AdaptiveMenuItem<AudioDevice>(
        value: device,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(12, 12),
              painter: _HeadphoneIconPainter(color: AppColors.textTertiary),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                device.shortName,
                style: AppTheme.inter(fontSize: 12, color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (device.isDefault) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: isDarkTheme ? 0.15 : 0.1),
                  borderRadius: BorderRadius.circular(isMacOS ? 4 : 3),
                ),
                child: Text(
                  l10n.defaultLabel,
                  style: AppTheme.inter(fontSize: 9, color: AppColors.accent, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ],
        ),
      )).toList(),
      onChanged: (device) {
        debugPrint('DeviceSelector.onChanged: ${device?.shortName}');
        if (device != null) onChanged(device);
      },
    );
  }
}

class _HeadphoneIconPainter extends CustomPainter {
  final Color color;
  _HeadphoneIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    final arcRect = Rect.fromLTWH(w * 0.1, h * 0.05, w * 0.8, h * 0.7);
    canvas.drawArc(arcRect, 3.14, 3.14, false, paint);

    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.05, h * 0.5, w * 0.25, h * 0.85, const Radius.circular(2)),
      paint,
    );

    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.75, h * 0.5, w * 0.95, h * 0.85, const Radius.circular(2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_HeadphoneIconPainter old) => old.color != color;
}
