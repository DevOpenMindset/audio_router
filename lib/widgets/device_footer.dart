import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../models/audio_models.dart';
import '../services/audio_service.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import 'adaptive_widgets.dart';
import 'peak_level_bar.dart';
import '../l10n/app_localizations.dart';

/// Bottom section showing all detected audio output devices with master volume sliders.
class DeviceFooter extends StatelessWidget {
  final List<AudioDevice> devices;
  final List<AudioSession> sessions;
  final String? defaultDeviceId;

  const DeviceFooter({
    super.key,
    required this.devices,
    required this.sessions,
    this.defaultDeviceId,
  });

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final l10n = context.l10n;
    final activeDevices = devices.where((d) => d.isActive).toList();
    final inactiveDevices = devices.where((d) => !d.isActive).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 0.5, color: AppColors.border),
        const SizedBox(height: 12),
        Text(
          l10n.audioOutputs,
          style: AppTheme.inter(fontSize: 11, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 8),
        // Active devices with volume sliders
        ...activeDevices.map((device) {
              // Aggregate peak across all sessions on this device
              final deviceSessions = sessions.where((s) {
                if (s.assignedDeviceId != null) return s.assignedDeviceId == device.id;
                return device.id == defaultDeviceId; // unrouted → on default
              });
              final peak = deviceSessions.isEmpty
                  ? 0.0
                  : deviceSessions.map((s) => s.peakLevel).reduce((a, b) => a > b ? a : b);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _DeviceVolumeRow(device: device, peak: peak),
              );
            }),
        // Inactive devices as compact tags
        if (inactiveDevices.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: inactiveDevices.map((d) => _InactiveTag(device: d)).toList(),
          ),
        ],
      ],
    );
  }
}

class _DeviceVolumeRow extends StatelessWidget {
  final AudioDevice device;
  final double peak;
  const _DeviceVolumeRow({required this.device, required this.peak});

  @override
  Widget build(BuildContext context) {
    final audioService = context.read<AudioService>();
    return Row(
      children: [
        // Status dot
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: device.isDefault ? AppColors.accent : AppColors.active,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        // Device name
        SizedBox(
          width: 90,
          child: Text(
            device.shortName,
            style: AppTheme.inter(
              fontSize: 11,
              color: device.isDefault ? AppColors.accent : AppColors.textSecondary,
              fontWeight: device.isDefault ? FontWeight.w500 : FontWeight.w400,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        // Audio activity indicator
        PeakLevelBar(
          level: peak,
          color: device.isDefault ? AppColors.accent : AppColors.active,
          width: 28,
          height: 3,
        ),
        const SizedBox(width: 6),
        // Master volume slider
        Expanded(
          child: AdaptiveSlider(
            value: device.volume,
            min: 0.0,
            max: 1.0,
            onChanged: (v) => audioService.setDeviceVolume(device.id, v),
          ),
        ),
        const SizedBox(width: 6),
        // Percentage label
        SizedBox(
          width: 28,
          child: Text(
            '${(device.volume * 100).round()}',
            textAlign: TextAlign.right,
            style: AppTheme.inter(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _InactiveTag extends StatelessWidget {
  final AudioDevice device;
  const _InactiveTag({required this.device});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.inactive,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            device.shortName,
            style: AppTheme.inter(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
