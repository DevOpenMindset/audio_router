import 'dart:ui';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' show Colors, BoxShadow;
import 'package:fluent_ui/fluent_ui.dart'
    hide Color, Colors, BoxShadow, Offset, FontWeight, Brightness, TextStyle;
import 'package:macos_ui/macos_ui.dart' as macos;
import 'package:provider/provider.dart';

import '../platform.dart';
import 'adaptive_widgets.dart';
import '../models/audio_models.dart';
import '../services/custom_name_service.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import 'app_icon.dart';
import 'peak_level_bar.dart';
import 'device_selector.dart';
import '../l10n/app_localizations.dart';

/// Card for an active audio session.
/// Fully custom — no Material Card, ListTile, etc.
class SessionCard extends StatefulWidget {
  final AudioSession session;
  final List<AudioDevice> devices;
  final AudioDevice? assignedDevice;
  final List<AudioDevice> mirrorDevices;
  final ValueChanged<AudioDevice> onDeviceChanged;
  final ValueChanged<AudioDevice>? onMirrorAdded;
  final ValueChanged<String>? onMirrorRemoved; // device ID
  final ValueChanged<double>? onVolumeChanged;
  final VoidCallback? onMuteToggle;

  const SessionCard({
    super.key,
    required this.session,
    required this.devices,
    required this.assignedDevice,
    this.mirrorDevices = const [],
    required this.onDeviceChanged,
    this.onMirrorAdded,
    this.onMirrorRemoved,
    this.onVolumeChanged,
    this.onMuteToggle,
  });

  @override
  State<SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<SessionCard> {
  bool _isHovered = false;
  bool _isRenaming = false;
  late TextEditingController _renameCtrl;
  late FocusNode _renameFocus;

  @override
  void initState() {
    super.initState();
    _renameCtrl = TextEditingController();
    _renameFocus = FocusNode();
    _renameFocus.addListener(() {
      if (!_renameFocus.hasFocus && _isRenaming && mounted) {
        _commitRename(context);
      }
    });
  }

  @override
  void dispose() {
    _renameCtrl.dispose();
    _renameFocus.dispose();
    super.dispose();
  }

  void _startRename(BuildContext context) {
    final names = context.read<CustomNameService>();
    final current =
        names.nameFor(widget.session.processName, widget.session.displayName);
    _renameCtrl.text = current;
    setState(() => _isRenaming = true);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _renameFocus.requestFocus());
  }

  void _commitRename(BuildContext context) {
    final names = context.read<CustomNameService>();
    names.setName(widget.session.processName, _renameCtrl.text);
    setState(() => _isRenaming = false);
  }

  void _resetName(BuildContext context) {
    context.read<CustomNameService>().resetName(widget.session.processName);
    setState(() => _isRenaming = false);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final appColor = AppColors.getAppColor(
      widget.session.processName,
      pid: widget.session.processId,
    );
    final names = context.watch<CustomNameService>();
    final displayName =
        names.nameFor(widget.session.processName, widget.session.displayName);
    final hasCustomName = names.hasCustomName(widget.session.processName);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: TweenAnimationBuilder<Color?>(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
        tween: ColorTween(
          begin: AppColors.accent,
          end: _isHovered ? appColor : AppColors.accent,
        ),
        builder: (context, animatedAccent, _) {
          // Subtle tinted background on hover
          final bgColor = _isHovered
              ? Color.lerp(AppColors.bgSecondary, appColor, 0.05)!
              : AppColors.bgSecondary;

          final borderColor = _isHovered
              ? animatedAccent!.withValues(alpha: 0.3)
              : (isDarkTheme ? Colors.transparent : AppColors.border);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppColors.cardRadius),
              border: Border.all(
                color: borderColor,
                width: 0.8,
              ),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: animatedAccent!.withValues(alpha: 0.08),
                        blurRadius: 15,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : AppColors.cardShadow,
            ),
            child: Column(
              children: [
                // Top row: icon + name + peak meter
                Row(
                  children: [
                    NativeAppIcon(
                      processId: widget.session.processId,
                      processName: widget.session.processName,
                      size: 34,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _isRenaming
                              ? SizedBox(
                                  height: 20,
                                  child: AdaptiveTextField(
                                    controller: _renameCtrl,
                                    focusNode: _renameFocus,
                                    style: AppTheme.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textPrimary,
                                    ),
                                    padding: EdgeInsets.zero,
                                    decoration: const BoxDecoration(),
                                    onSubmitted: (_) => _commitRename(context),
                                  ),
                                )
                              : GestureDetector(
                                  onDoubleTap: () => _startRename(context),
                                  onSecondaryTap: hasCustomName
                                      ? () => _resetName(context)
                                      : null,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        displayName,
                                        style: AppTheme.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      if (hasCustomName) ...[
                                        const SizedBox(width: 4),
                                        Text(
                                          '✎',
                                          style: AppTheme.inter(
                                            fontSize: 9,
                                            color: AppColors.textTertiary,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                          if (widget.session.subtitle != null) ...[
                            const SizedBox(height: 1),
                            Text(
                              widget.session.subtitle!,
                              style: AppTheme.inter(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    PeakLevelBar(
                      level: widget.session.peakLevel,
                      color: animatedAccent ?? AppColors.accent,
                      width: 52,
                      height: 3,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Volume slider row
                _VolumeRow(
                  volume: widget.session.volume,
                  isMuted: widget.session.isMuted,
                  color: animatedAccent!,
                  onVolumeChanged: widget.onVolumeChanged,
                  onMuteToggle: widget.onMuteToggle,
                ),
                const SizedBox(height: 8),
                // Bottom row: device selector
                DeviceSelector(
                  selectedDevice: widget.assignedDevice,
                  devices: widget.devices,
                  onChanged: widget.onDeviceChanged,
                ),
                // Mirror outputs row
                if (widget.onMirrorAdded != null) ...[
                  const SizedBox(height: 6),
                  _MirrorRow(
                    mirrorDevices: widget.mirrorDevices,
                    availableDevices: widget.devices
                        .where((d) =>
                            d.isActive &&
                            d.id != (widget.assignedDevice?.id ?? '') &&
                            !widget.mirrorDevices.any((m) => m.id == d.id))
                        .toList(),
                    onAdd: widget.onMirrorAdded!,
                    onRemove: widget.onMirrorRemoved,
                    accentColor: animatedAccent ?? AppColors.accent,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  final double volume;
  final bool isMuted;
  final Color color;
  final ValueChanged<double>? onVolumeChanged;
  final VoidCallback? onMuteToggle;

  const _VolumeRow({
    required this.volume,
    required this.isMuted,
    required this.color,
    this.onVolumeChanged,
    this.onMuteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isMuted ? AppColors.textTertiary : color;
    return Row(
      children: [
        if (isMacOS)
          macos.MacosIconButton(
            icon: macos.MacosIcon(
              isMuted ? CupertinoIcons.speaker_slash : CupertinoIcons.speaker_2,
              size: 14,
              color: effectiveColor,
            ),
            onPressed: onMuteToggle,
            backgroundColor: Colors.transparent,
            hoverColor: AppColors.bgHover,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(4),
            boxConstraints: const BoxConstraints(
              minWidth: 22,
              minHeight: 22,
              maxWidth: 22,
              maxHeight: 22,
            ),
          )
        else
          GestureDetector(
            onTap: onMuteToggle,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: SizedBox(
                width: 20,
                height: 20,
                child: CustomPaint(
                  painter: isMuted
                      ? _MutedSpeakerPainter(color: AppColors.textTertiary)
                      : _SpeakerPainter(color: effectiveColor),
                ),
              ),
            ),
          ),
        const SizedBox(width: 4),
        Expanded(
          child: AdaptiveSlider(
            value: volume,
            min: 0.0,
            max: 1.0,
            onChanged: isMuted ? null : onVolumeChanged,
            activeColor: effectiveColor,
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 32,
          child: Text(
            '${(volume * 100).round()}',
            textAlign: TextAlign.right,
            style: AppTheme.inter(
              fontSize: 11,
              color: isMuted ? AppColors.textTertiary : AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
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

    final cx = size.width / 2;
    final cy = size.height / 2;

    canvas.drawLine(Offset(cx - 4, cy - 2), Offset(cx - 4, cy + 2), paint);
    canvas.drawLine(Offset(cx - 4, cy - 2), Offset(cx - 1, cy - 4), paint);
    canvas.drawLine(Offset(cx - 4, cy + 2), Offset(cx - 1, cy + 4), paint);

    final wave = Path()
      ..moveTo(cx + 1, cy - 2.5)
      ..quadraticBezierTo(cx + 3.5, cy, cx + 1, cy + 2.5);
    canvas.drawPath(wave, paint);
  }

  @override
  bool shouldRepaint(_SpeakerPainter old) => old.color != color;
}

class _MutedSpeakerPainter extends CustomPainter {
  final Color color;
  _MutedSpeakerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    canvas.drawLine(Offset(cx - 4, cy - 2), Offset(cx - 4, cy + 2), paint);
    canvas.drawLine(Offset(cx - 4, cy - 2), Offset(cx - 1, cy - 4), paint);
    canvas.drawLine(Offset(cx - 4, cy + 2), Offset(cx - 1, cy + 4), paint);

    canvas.drawLine(Offset(cx + 1, cy - 2), Offset(cx + 5, cy + 2), paint);
    canvas.drawLine(Offset(cx + 5, cy - 2), Offset(cx + 1, cy + 2), paint);
  }

  @override
  bool shouldRepaint(_MutedSpeakerPainter old) => old.color != color;
}

/// Row showing active mirror outputs + a button to add more.
class _MirrorRow extends StatelessWidget {
  final List<AudioDevice> mirrorDevices;
  final List<AudioDevice> availableDevices;
  final ValueChanged<AudioDevice> onAdd;
  final ValueChanged<String>? onRemove;
  final Color accentColor;

  const _MirrorRow({
    required this.mirrorDevices,
    required this.availableDevices,
    required this.onAdd,
    this.onRemove,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Mirror chips
        ...mirrorDevices.map((device) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _MirrorChip(
                label: device.shortName,
                onRemove: onRemove != null ? () => onRemove!(device.id) : null,
                accentColor: accentColor,
              ),
            )),
        // Add button (only if there are available devices)
        if (availableDevices.isNotEmpty)
          _AddMirrorButton(
            devices: availableDevices,
            onSelected: onAdd,
            hasExisting: mirrorDevices.isNotEmpty,
          ),
      ],
    );
  }
}

class _MirrorChip extends StatelessWidget {
  final String label;
  final VoidCallback? onRemove;
  final Color accentColor;

  const _MirrorChip(
      {required this.label, this.onRemove, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTheme.inter(
              fontSize: 10,
              color: accentColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 3),
            GestureDetector(
              onTap: onRemove,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Icon(
                  FluentIcons.cancel,
                  size: 8,
                  color: accentColor.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddMirrorButton extends StatelessWidget {
  final List<AudioDevice> devices;
  final ValueChanged<AudioDevice> onSelected;
  final bool hasExisting;

  const _AddMirrorButton({
    required this.devices,
    required this.onSelected,
    required this.hasExisting,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.add, size: 9, color: AppColors.textTertiary),
              const SizedBox(width: 3),
              Text(
                hasExisting ? context.l10n.audioOutputs : context.l10n.addRule, // Reusing existing keys or I should add specific ones
                style:
                    AppTheme.inter(fontSize: 10, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.15),
      builder: (ctx) => ContentDialog(
        constraints: const BoxConstraints(maxWidth: 280),
        title: Text(
          'Ajouter une sortie',
          style: AppTheme.inter(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: devices
              .map((device) => ListTile(
                    title: Text(
                      context.l10n.localizeDeviceName(device.shortName),
                      style: AppTheme.inter(
                          fontSize: 12, color: AppColors.textPrimary),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      onSelected(device);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }
}

/// Card for an inactive/silent session
class InactiveSessionCard extends StatelessWidget {
  final AudioSession session;

  const InactiveSessionCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final l10n = context.l10n;
    if (isMacOS) {
      return macos.MacosListTile(
        leading: const InactiveAppIcon(size: 28),
        leadingWhitespace: 10,
        title: Text(
          session.displayName,
          style: AppTheme.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textTertiary,
          ),
        ),
        subtitle: Text(
          l10n.noAudio,
          style: AppTheme.inter(fontSize: 11, color: AppColors.textTertiary),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDarkTheme
            ? AppColors.bgSecondary.withValues(alpha: 0.45)
            : AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        border: isDarkTheme
            ? null
            : Border.all(color: AppColors.border, width: 0.5),
        boxShadow: isDarkTheme ? [] : AppColors.cardShadow,
      ),
      child: Row(
        children: [
          const InactiveAppIcon(size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              session.displayName,
              style: AppTheme.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          Text(
            l10n.noAudio,
            style: AppTheme.inter(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
