import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'adaptive_widgets.dart';
import 'device_icon.dart';
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
            DeviceIcon(device: device, size: 12),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.localizeDeviceName(device.shortName),
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
