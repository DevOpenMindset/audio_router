import 'dart:io' show Platform;
import '../platform.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:macos_ui/macos_ui.dart' as macos;
import 'package:provider/provider.dart';
import 'adaptive_widgets.dart';
import '../models/audio_models.dart';
import '../services/audio_service.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

/// Panel for managing app rules (auto-route when app opens).
class AppRulesPanel extends StatelessWidget {
  const AppRulesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final l10n = context.l10n;
    return Consumer<AudioService>(
      builder: (context, audioService, _) {
        final rules   = audioService.appRules;
        final sessions = audioService.sessions;
        final devices  = audioService.devices;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text('⚡', style: AppTheme.inter(fontSize: 12)),
                const SizedBox(width: 6),
                Text(
                  l10n.appRules,
                  style: AppTheme.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                _AddRuleButton(
                  sessions: sessions,
                  devices: devices,
                  onAdd: (rule) => audioService.addAppRule(rule),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (rules.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.bgSecondary,
                  borderRadius: BorderRadius.circular(AppColors.cardRadius),
                  border: isDarkTheme
                      ? Border.all(color: AppColors.border, width: 0.5)
                      : null,
                  boxShadow: isDarkTheme ? [] : AppColors.cardShadow,
                ),
                child: Column(
                  children: [
                    Text(
                      l10n.noAppRules,
                      style: AppTheme.inter(fontSize: 12, color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.noAppRulesHint,
                      style: AppTheme.inter(fontSize: 11, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              )
            else
              ...rules.map((rule) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _AppRuleCard(
                  rule: rule,
                  onToggle: () => audioService.updateAppRule(
                    rule.copyWith(enabled: !rule.enabled),
                  ),
                  onDelete: () => audioService.removeAppRule(rule.id),
                ),
              )),
          ],
        );
      },
    );
  }
}

// ─── Rule Card ───────────────────────────────────────────────

class _AppRuleCard extends StatefulWidget {
  final AppRule rule;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _AppRuleCard({
    required this.rule,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  State<_AppRuleCard> createState() => _AppRuleCardState();
}

class _AppRuleCardState extends State<_AppRuleCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.rule.enabled ? AppColors.accent : AppColors.textTertiary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit:  (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _isHovered ? AppColors.bgTertiary : AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          border: Border.all(
            color: _isHovered ? AppColors.borderHover
                              : (isDarkTheme ? Colors.transparent : AppColors.border),
            width: 0.5,
          ),
          boxShadow: isDarkTheme ? [] : AppColors.cardShadow,
        ),
        child: Row(
          children: [
            // Rule label: "App → Device"
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: AppTheme.inter(fontSize: 12, color: AppColors.textSecondary),
                  children: [
                    TextSpan(
                      text: widget.rule.triggerDisplayName,
                      style: AppTheme.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: widget.rule.enabled
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                      ),
                    ),
                    TextSpan(
                      text: '  →  ',
                      style: AppTheme.inter(fontSize: 11, color: color),
                    ),
                    TextSpan(
                      text: widget.rule.deviceName,
                      style: AppTheme.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: widget.rule.enabled
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Toggle
            AdaptiveToggle(
              checked: widget.rule.enabled,
              onChanged: (_) => widget.onToggle(),
            ),

            // Delete (on hover)
            if (_isHovered) ...[
              const SizedBox(width: 6),
              if (isMacOS)
                macos.MacosIconButton(
                  icon: macos.MacosIcon(
                    CupertinoIcons.trash,
                    size: 12,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: widget.onDelete,
                  backgroundColor: Colors.transparent,
                  hoverColor: AppColors.bgHover,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(4),
                  boxConstraints: const BoxConstraints(
                    minWidth: 20, minHeight: 20,
                    maxWidth: 20, maxHeight: 20,
                  ),
                )
              else
                GestureDetector(
                  onTap: widget.onDelete,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('✕',
                      style: AppTheme.inter(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      )),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Add Rule Button ─────────────────────────────────────────

class _AddRuleButton extends StatefulWidget {
  final List<AudioSession> sessions;
  final List<AudioDevice> devices;
  final ValueChanged<AppRule> onAdd;

  const _AddRuleButton({
    required this.sessions,
    required this.devices,
    required this.onAdd,
  });

  @override
  State<_AddRuleButton> createState() => _AddRuleButtonState();
}

class _AddRuleButtonState extends State<_AddRuleButton> {
  bool _isHovered = false;

  void _showAddDialog() {
    final l10n = context.l10n;
    if (widget.sessions.isEmpty || widget.devices.isEmpty) return;

    final appNames = widget.sessions
        .map((s) => (processName: s.processName, displayName: s.displayName))
        .toSet()
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    var selectedApp = appNames.first;
    var selectedDevice = widget.devices.first;

    showAdaptiveStatefulDialog(
      context: context,
      title: l10n.newAppRule,
      contentBuilder: (setDialogState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.whenAppOpens,
            style: AppTheme.inter(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          AdaptiveComboBox<String>(
            value: selectedApp.processName,
            isExpanded: true,
            style: AppTheme.inter(fontSize: 12, color: AppColors.textPrimary),
            items: appNames.map((a) => AdaptiveMenuItem<String>(
              value: a.processName,
              child: Text(a.displayName,
                style: AppTheme.inter(fontSize: 12, color: AppColors.textPrimary)),
            )).toList(),
            onChanged: (v) {
              if (v == null) return;
              setDialogState(() {
                selectedApp = appNames.firstWhere((a) => a.processName == v,
                    orElse: () => appNames.first);
              });
            },
          ),

          const SizedBox(height: 14),
          Text(
            l10n.routeToDevice,
            style: AppTheme.inter(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          AdaptiveComboBox<String>(
            value: selectedDevice.id,
            isExpanded: true,
            style: AppTheme.inter(fontSize: 12, color: AppColors.textPrimary),
            items: widget.devices.map((d) => AdaptiveMenuItem<String>(
              value: d.id,
              child: Row(
                children: [
                  Text('🎧 ',
                    style: AppTheme.inter(fontSize: 12)),
                  Expanded(
                    child: Text(d.shortName,
                      style: AppTheme.inter(fontSize: 12, color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            )).toList(),
            onChanged: (v) {
              if (v == null) return;
              setDialogState(() {
                selectedDevice = widget.devices.firstWhere((d) => d.id == v,
                    orElse: () => widget.devices.first);
              });
            },
          ),
        ],
      ),
      confirmLabel: l10n.add,
      onConfirm: (ctx, setDialogState) => () {
        widget.onAdd(AppRule(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          triggerProcessName: selectedApp.processName,
          triggerDisplayName: selectedApp.displayName,
          deviceId: selectedDevice.id,
          deviceName: selectedDevice.shortName,
          enabled: true,
        ));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit:  (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _showAddDialog,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _isHovered ? AppColors.bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
            border: Border.all(
              color: _isHovered ? AppColors.borderHover : AppColors.border,
              width: 0.5,
            ),
          ),
          child: Text(
            context.l10n.addRule,
            style: AppTheme.inter(
              fontSize: 11,
              color: _isHovered ? AppColors.textSecondary : AppColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
