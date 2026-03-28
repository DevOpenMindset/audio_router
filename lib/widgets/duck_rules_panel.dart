import '../platform.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:macos_ui/macos_ui.dart' as macos;
import 'adaptive_widgets.dart';
import 'package:provider/provider.dart';
import '../models/audio_models.dart';
import '../services/audio_service.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

/// Panel for managing auto-duck rules.
/// Shows existing rules and allows creating new ones.
class DuckRulesPanel extends StatelessWidget {
  const DuckRulesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final l10n = context.l10n;
    return Consumer<AudioService>(
      builder: (context, audioService, _) {
        final rules = audioService.duckRules;
        final allSessions = audioService.sessions;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CustomPaint(
                  size: const Size(14, 14),
                  painter: _DuckIconPainter(),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.autoDuck,
                  style: AppTheme.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                _AddRuleButton(
                  sessions: allSessions,
                  onAdd: (rule) => audioService.addDuckRule(rule),
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
                      l10n.noRules,
                      style: AppTheme.inter(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.noRulesHint,
                      style: AppTheme.inter(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...rules.map((rule) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _DuckRuleCard(
                  rule: rule,
                  isDucking: audioService.isSessionDucked(rule.targetProcessName),
                  onToggle: () {
                    audioService.updateDuckRule(
                      rule.copyWith(enabled: !rule.enabled),
                    );
                  },
                  onDelete: () => audioService.removeDuckRule(rule.id),
                  onVolumeChanged: (vol) {
                    audioService.updateDuckRule(
                      rule.copyWith(duckedVolume: vol),
                    );
                  },
                ),
              )),
          ],
        );
      },
    );
  }
}

// ─── Duck Rule Card ──────────────────────────────────────────

class _DuckRuleCard extends StatefulWidget {
  final DuckRule rule;
  final bool isDucking;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final ValueChanged<double> onVolumeChanged;

  const _DuckRuleCard({
    required this.rule,
    required this.isDucking,
    required this.onToggle,
    required this.onDelete,
    required this.onVolumeChanged,
  });

  @override
  State<_DuckRuleCard> createState() => _DuckRuleCardState();
}

class _DuckRuleCardState extends State<_DuckRuleCard> {
  bool _isHovered = false;
  bool _isDragging = false;
  late double _localVolume;

  @override
  void initState() {
    super.initState();
    _localVolume = widget.rule.duckedVolume;
  }

  @override
  void didUpdateWidget(_DuckRuleCard old) {
    super.didUpdateWidget(old);
    if (!_isDragging && widget.rule.duckedVolume != _localVolume) {
      _localVolume = widget.rule.duckedVolume;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.rule.enabled
        ? AppColors.accent
        : AppColors.textTertiary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _isHovered ? AppColors.bgTertiary : AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          border: Border.all(
            color: widget.isDucking
                ? AppColors.accent.withValues(alpha: 0.4)
                : _isHovered
                    ? AppColors.borderHover
                    : (isDarkTheme ? Colors.transparent : AppColors.border),
            width: 0.5,
          ),
          boxShadow: isDarkTheme ? [] : AppColors.cardShadow,
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Active indicator
                if (widget.isDucking)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.4),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                // Rule description
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: AppTheme.inter(fontSize: 12, color: AppColors.textSecondary),
                      children: [
                        TextSpan(
                          text: widget.rule.triggerProcessName,
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
                          style: AppTheme.inter(
                            fontSize: 11,
                            color: color,
                          ),
                        ),
                        TextSpan(
                          text: widget.rule.targetProcessName,
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
                // Delete
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
                        minWidth: 20,
                        minHeight: 20,
                        maxWidth: 20,
                        maxHeight: 20,
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: widget.onDelete,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: CustomPaint(
                          size: const Size(12, 12),
                          painter: _TrashIconPainter(color: AppColors.textTertiary),
                        ),
                      ),
                    ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            // Ducked volume slider
            Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    '${(_localVolume * 100).round()}%',
                    style: AppTheme.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: widget.rule.enabled ? color : AppColors.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: AdaptiveSlider(
                    value: _localVolume,
                    onChanged: widget.rule.enabled
                        ? (v) => setState(() {
                              _localVolume = v;
                              _isDragging = true;
                            })
                        : null,
                    onChangeEnd: widget.rule.enabled
                        ? (v) {
                            setState(() => _isDragging = false);
                            widget.onVolumeChanged(v);
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


// ─── Add Rule Button ─────────────────────────────────────────

class _AddRuleButton extends StatefulWidget {
  final List<AudioSession> sessions;
  final ValueChanged<DuckRule> onAdd;

  const _AddRuleButton({
    required this.sessions,
    required this.onAdd,
  });

  @override
  State<_AddRuleButton> createState() => _AddRuleButtonState();
}

class _AddRuleButtonState extends State<_AddRuleButton> {
  bool _isHovered = false;

  void _showAddDialog() {
    final l10n = context.l10n;
    final appNames = widget.sessions
        .map((s) => s.processName)
        .toSet()
        .toList()
      ..sort();

    if (appNames.isEmpty) return;

    String? trigger = appNames.first;
    String? target = appNames.length > 1 ? appNames[1] : appNames.first;
    double volume = 0.3;

    showAdaptiveStatefulDialog(
      context: context,
      title: l10n.newDuckRule,
      contentBuilder: (setDialogState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.whenAppActive,
            style: AppTheme.inter(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          _AppDropdown(
            value: trigger!,
            items: appNames,
            onChanged: (v) => setDialogState(() => trigger = v),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.lowerAppTo,
            style: AppTheme.inter(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          _AppDropdown(
            value: target!,
            items: appNames,
            onChanged: (v) => setDialogState(() => target = v),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '${(volume * 100).round()}%',
                style: AppTheme.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdaptiveSlider(
                  value: volume,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (v) => setDialogState(() => volume = v),
                ),
              ),
            ],
          ),
        ],
      ),
      confirmLabel: l10n.add,
      onConfirm: (ctx, setDialogState) => () {
        if (trigger != null && target != null && trigger != target) {
          widget.onAdd(DuckRule(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            triggerProcessName: trigger!,
            targetProcessName: target!,
            duckedVolume: volume,
            enabled: true,
          ));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
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

// ─── App Dropdown ────────────────────────────────────────────

class _AppDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _AppDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveComboBox<String>(
      value: value,
      isExpanded: true,
      style: AppTheme.inter(fontSize: 12, color: AppColors.textPrimary),
      items: items.map((name) => AdaptiveMenuItem<String>(
        value: name,
        child: Text(name, style: AppTheme.inter(fontSize: 12, color: AppColors.textPrimary)),
      )).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    );
  }
}

// ─── Custom Painters ─────────────────────────────────────────

class _DuckIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textTertiary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Volume down arrow
    canvas.drawLine(Offset(cx - 4, cy - 3), Offset(cx, cy + 1), paint);
    canvas.drawLine(Offset(cx, cy + 1), Offset(cx + 4, cy - 3), paint);
    canvas.drawLine(Offset(cx - 4, cy + 1), Offset(cx, cy + 5), paint);
    canvas.drawLine(Offset(cx, cy + 5), Offset(cx + 4, cy + 1), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _TrashIconPainter extends CustomPainter {
  final Color color;
  _TrashIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // Lid
    canvas.drawLine(Offset(w * 0.15, h * 0.25), Offset(w * 0.85, h * 0.25), paint);
    canvas.drawLine(Offset(w * 0.35, h * 0.25), Offset(w * 0.35, h * 0.12), paint);
    canvas.drawLine(Offset(w * 0.35, h * 0.12), Offset(w * 0.65, h * 0.12), paint);
    canvas.drawLine(Offset(w * 0.65, h * 0.12), Offset(w * 0.65, h * 0.25), paint);

    // Body
    canvas.drawLine(Offset(w * 0.22, h * 0.25), Offset(w * 0.28, h * 0.88), paint);
    canvas.drawLine(Offset(w * 0.28, h * 0.88), Offset(w * 0.72, h * 0.88), paint);
    canvas.drawLine(Offset(w * 0.72, h * 0.88), Offset(w * 0.78, h * 0.25), paint);
  }

  @override
  bool shouldRepaint(_TrashIconPainter old) => old.color != color;
}

