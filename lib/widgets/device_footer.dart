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
  // Hidden when embedded under an external header (e.g. the collapsible
  // device-volumes section on the Apps tab).
  final bool showHeader;

  const DeviceFooter({
    super.key,
    required this.devices,
    required this.sessions,
    this.defaultDeviceId,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final themeService = context.read<ThemeService>();
    final l10n = context.l10n;
    final activeDevices = devices.where((d) => d.isActive).toList();
    final inactiveDevices = devices.where((d) => !d.isActive).toList();
    
    // Get OS accent color if sync is enabled, otherwise use default accent
    final accentColor = themeService.useOSAccent && themeService.accentColor != null
        ? Color(themeService.accentColor!.value)
        : AppColors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Container(height: 0.5, color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                l10n.audioOutputs,
                style: AppTheme.inter(fontSize: 11, color: AppColors.textTertiary),
              ),
              const Spacer(),
              // Mute all toggle
              _MiniActionButton(
                label: context.watch<AudioService>().allMuted ? '🔇' : '🔊',
                tooltip: context.read<AudioService>().allMuted ? l10n.unmuteAll : l10n.muteAll,
                onTap: () => context.read<AudioService>().toggleMuteAll(),
                accentColor: accentColor,
              ),
              const SizedBox(width: 6),
              // Open OS sound settings
              _MiniActionButton(
                label: '⚙',
                tooltip: l10n.openSoundSettings,
                onTap: () => context.read<AudioService>().openSoundSettings(),
                accentColor: accentColor,
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
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

class _DeviceVolumeRow extends StatefulWidget {
  final AudioDevice device;
  final double peak;
  const _DeviceVolumeRow({required this.device, required this.peak});

  @override
  State<_DeviceVolumeRow> createState() => _DeviceVolumeRowState();
}

class _DeviceVolumeRowState extends State<_DeviceVolumeRow> {
  bool _expanded = false;
  double _balance = 0.0;
  bool _balanceLoaded = false;

  void _loadBalance() {
    if (_balanceLoaded) return;
    final svc = context.read<AudioService>();
    _balance = svc.getDeviceBalance(widget.device.id);
    _balanceLoaded = true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final audioService = context.read<AudioService>();
    final themeService = context.read<ThemeService>();
    final device = widget.device;
    if (_expanded && !_balanceLoaded) _loadBalance();
    
    // Get OS accent color if sync is enabled, otherwise use default accent
    final accentColor = themeService.useOSAccent && themeService.accentColor != null
        ? Color(themeService.accentColor!.value)
        : AppColors.accent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: device.isDefault ? Border.all(color: accentColor.withValues(alpha: 0.3), width: 0.5) : null,
          ),
          child: Row(
            children: [
            // Expand toggle
            GestureDetector(
              onTap: () => setState(() { _expanded = !_expanded; _balanceLoaded = false; }),
              child: Icon(
                _expanded ? FluentIcons.chevron_down : FluentIcons.chevron_right,
                size: 8,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 4),
            // Status dot
            Container(
              width: 4, height: 4,
              decoration: BoxDecoration(
                color: device.isDefault ? accentColor : AppColors.active,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            // Device name
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () => setState(() { _expanded = !_expanded; _balanceLoaded = false; }),
                child: Text(
                  l10n.localizeDeviceName(device.shortName),
                  style: AppTheme.inter(
                    fontSize: 11,
                    color: device.isDefault ? accentColor : AppColors.textSecondary,
                    fontWeight: device.isDefault ? FontWeight.w500 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Peak level
            PeakLevelBar(
              level: widget.peak,
              color: device.isDefault ? accentColor : AppColors.active,
              width: 28, height: 3,
            ),
            const SizedBox(width: 6),
            // Master volume slider
            Expanded(
              flex: 4,
              child: AdaptiveSlider(
                value: device.volume,
                min: 0.0, max: 1.0,
                onChanged: (v) => audioService.setDeviceVolume(device.id, v),
              ),
            ),
            const SizedBox(width: 6),
            // Percentage
            SizedBox(
              width: 28,
              child: Text(
                '${(device.volume * 100).round()}',
                textAlign: TextAlign.right,
                style: AppTheme.inter(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w500),
              ),
            ),
            ],
          ),
        ),
        // ── Expanded section: set default + balance ──
        if (_expanded) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Row(
              children: [
                // Set as default button
                if (!device.isDefault)
                  _MiniActionButton(
                    label: '★',
                    tooltip: l10n.setDefault,
                    onTap: () => audioService.setDefaultDevice(device.id),
                    accentColor: accentColor,
                  ),
                if (!device.isDefault) const SizedBox(width: 8),
                // Balance label
                Text('L', style: AppTheme.inter(fontSize: 9, color: AppColors.textTertiary)),
                const SizedBox(width: 4),
                // Balance slider
                Expanded(
                  child: AdaptiveSlider(
                    value: (_balance + 1.0) / 2.0, // map -1..+1 to 0..1
                    min: 0.0, max: 1.0,
                    onChanged: (v) {
                      final bal = v * 2.0 - 1.0; // map 0..1 to -1..+1
                      setState(() => _balance = bal);
                      audioService.setDeviceBalance(device.id, bal);
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Text('R', style: AppTheme.inter(fontSize: 9, color: AppColors.textTertiary)),
                const SizedBox(width: 8),
                // Balance value
                SizedBox(
                  width: 28,
                  child: Text(
                    _balance.abs() < 0.05 ? 'C' : '${(_balance * 100).round()}',
                    textAlign: TextAlign.right,
                    style: AppTheme.inter(fontSize: 9, color: AppColors.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MiniActionButton extends StatefulWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final Color accentColor;
  const _MiniActionButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
    required this.accentColor,
  });
  @override
  State<_MiniActionButton> createState() => _MiniActionButtonState();
}

class _MiniActionButtonState extends State<_MiniActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // PlainTooltip, not fluent_ui Tooltip: this widget renders inside the
    // MacosApp tree too, where FluentTheme.of crashes (grey settings tab).
    return PlainTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _hovered ? widget.accentColor.withValues(alpha: 0.15) : AppColors.bgSecondary,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Text(
              widget.label,
              style: AppTheme.inter(fontSize: 10, color: widget.accentColor, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

class _InactiveTag extends StatelessWidget {
  final AudioDevice device;
  const _InactiveTag({required this.device});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
            l10n.localizeDeviceName(device.shortName),
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
