import '../platform.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:macos_ui/macos_ui.dart' as macos;
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../services/theme_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/adaptive_widgets.dart';
import '../widgets/donation_dialog.dart';
import '../l10n/app_localizations.dart';

class SettingsScreen extends StatelessWidget {
  /// If true, renders as a plain scrollable content (no dialog chrome).
  final bool inline;
  const SettingsScreen({super.key, this.inline = false});

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    if (isMacOS) return _buildMacOS(context);

    final content = _buildWindowsContent(context);

    // Inline mode: no dialog wrapper, just content
    if (inline) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: content,
      );
    }

    // Dialog mode: wrapped in a card
    final l10n = context.l10n;
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppColors.dialogRadius),
        border: isDarkTheme ? Border.all(color: AppColors.border, width: 0.5) : null,
        boxShadow: AppColors.dialogShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(l10n.settings,
                    style: AppTheme.inter(
                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: Icon(adaptiveCloseIcon(), size: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),
          content,
        ],
      ),
    );
  }

  Widget _buildWindowsContent(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Consumer<AudioService>(
          builder: (context, audioService, _) {
            final l = context.l10n;
            return _SettingToggle(
              label: l.launchStartup,
              description: l.launchStartupDescWin,
              value: audioService.autostart,
              onChanged: (val) => audioService.setAutostart(val),
            );
          },
        ),
        Consumer<ThemeService>(
          builder: (context, themeService, _) {
            final l = context.l10n;
            return _SettingToggle(
              label: l.showInTaskbar,
              description: l.showInTaskbarDesc,
              value: themeService.showInTaskbar,
              onChanged: (val) => themeService.setShowInTaskbar(val),
            );
          },
        ),
        Consumer<ThemeService>(
          builder: (context, themeService, _) {
            final l = context.l10n;
            return _SettingToggle(
              label: l.darkMode,
              description: l.darkModeDesc,
              value: themeService.isDarkMode,
              onChanged: (val) => themeService.setDarkMode(val),
            );
          },
        ),
        Consumer<ThemeService>(
          builder: (context, themeService, _) => _UIStylePicker(
            current: themeService.uiStyle,
            onChanged: (style) => themeService.setUIStyle(style),
          ),
        ),
        Consumer<ThemeService>(
          builder: (context, themeService, _) => _LocalePicker(
            current: themeService.locale,
            onChanged: (l) => themeService.setLocale(l),
          ),
        ),
        Container(height: 1, color: AppColors.border),
        _SettingAction(
          label: l10n.supportProject,
          description: l10n.donateCoffee,
          icon: '☕',
          onTap: () => openUrl(kCoffeeUrl),
        ),
        const SizedBox(height: 8),
        Consumer<UpdateService>(
          builder: (context, updateService, _) => _SettingToggle(
            label: l10n.checkUpdates,
            description: l10n.updateBody.split('\n').first,
            value: updateService.checkAutoUpdates,
            onChanged: (v) => updateService.setCheckAutoUpdates(v),
          ),
        ),
        Container(height: 1, color: AppColors.border),
        const _VersionTile(),
      ],
    );
  }

  // ─── macOS Build ─────────────────────────────────────────

  Widget _buildMacOS(BuildContext context) {
    final l10n = context.l10n;
    return ColoredBox(
      color: AppColors.bgSecondary,
      child: SizedBox(
        width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Text(
                  l10n.settings,
                  style: AppTheme.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                macos.PushButton(
                  controlSize: macos.ControlSize.small,
                  secondary: true,
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.done),
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: AppColors.border),
          const SizedBox(height: 4),

          // General section
          _macSection(l10n.general),
          Consumer<AudioService>(
            builder: (ctx, audioService, _) {
              final l = ctx.l10n;
              return _macToggle(
                context: ctx,
                icon: CupertinoIcons.rocket,
                label: l.launchStartup,
                subtitle: l.launchStartupDescMac,
                value: audioService.autostart,
                onChanged: (v) => audioService.setAutostart(v),
              );
            },
          ),
          Consumer<ThemeService>(
            builder: (ctx, themeService, _) {
              final l = ctx.l10n;
              return _macToggle(
                context: ctx,
                icon: CupertinoIcons.moon_stars,
                label: l.darkMode,
                subtitle: l.darkModeDesc,
                value: themeService.isDarkMode,
                onChanged: (v) => themeService.setDarkMode(v),
              );
            },
          ),
          Consumer<ThemeService>(
            builder: (ctx, themeService, _) {
              final l = ctx.l10n;
              return _macToggle(
                context: ctx,
                icon: CupertinoIcons.square_stack,
                label: l.showInDock,
                subtitle: l.showInTaskbarDesc,
                value: themeService.showInTaskbar,
                onChanged: (v) => themeService.setShowInTaskbar(v),
              );
            },
          ),

          // UI style picker
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Consumer<ThemeService>(
              builder: (ctx, themeService, _) => _UIStylePicker(
                current: themeService.uiStyle,
                onChanged: (s) => themeService.setUIStyle(s),
              ),
            ),
          ),

          // Language picker
          Consumer<ThemeService>(
            builder: (ctx, themeService, _) => _LocalePicker(
              current: themeService.locale,
              onChanged: (l) => themeService.setLocale(l),
            ),
          ),

          // Updates
          Consumer<UpdateService>(
            builder: (ctx, updateService, _) => _macToggle(
              context: context,
              icon: CupertinoIcons.cloud_download,
              label: l10n.checkUpdates,
              value: updateService.checkAutoUpdates,
              onChanged: (v) => updateService.setCheckAutoUpdates(v),
            ),
          ),
          Container(height: 0.5, color: AppColors.border),
          const SizedBox(height: 4),

          // Donation
          _macAction(
            context: context,
            icon: CupertinoIcons.heart,
            label: l10n.supportProject,
            subtitle: l10n.donateCoffee,
            onTap: () => openUrl(kCoffeeUrl),
          ),

          Container(height: 0.5, color: AppColors.border),
          const _VersionTile(),
          const SizedBox(height: 20),
        ],
      ), // Column
      ), // SizedBox
    ); // ColoredBox
  }

  Widget _macSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: AppTheme.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _macToggle({
    required BuildContext context,
    required IconData icon,
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          macos.MacosIcon(icon, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.inter(fontSize: 13, color: AppColors.textPrimary),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: AppTheme.inter(fontSize: 11, color: AppColors.textTertiary),
                  ),
              ],
            ),
          ),
          macos.MacosSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: macos.MacosColor(AppColors.accent.toARGB32()),
          ),
        ],
      ),
    );
  }

  Widget _macAction({
    required BuildContext context,
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              macos.MacosIcon(icon, size: 16, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTheme.inter(fontSize: 13, color: AppColors.accent),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: AppTheme.inter(fontSize: 11, color: AppColors.textTertiary),
                      ),
                  ],
                ),
              ),
              macos.MacosIcon(
                CupertinoIcons.chevron_right,
                size: 12,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _SettingToggle extends StatefulWidget {
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingToggle({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_SettingToggle> createState() => _SettingToggleState();
}

class _SettingToggleState extends State<_SettingToggle> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: _isHovered ? AppColors.bgHover : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: AppTheme.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.description,
                      style: AppTheme.inter(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AdaptiveToggle(
                checked: widget.value,
                onChanged: widget.onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── UI Style Picker ─────────────────────────────────────────

class _UIStylePicker extends StatelessWidget {
  final String current; // 'win' or 'mac'
  final ValueChanged<String> onChanged;

  const _UIStylePicker({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.interfaceStyle,
            style: AppTheme.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.interfaceStyleDesc,
            style: AppTheme.inter(fontSize: 10, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StyleOption(
                  label: 'Windows 11',
                  emoji: '🪟',
                  value: 'win',
                  selected: current == 'win',
                  onTap: () => onChanged('win'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StyleOption(
                  label: 'macOS',
                  emoji: '🍎',
                  value: 'mac',
                  selected: current == 'mac',
                  onTap: () => onChanged('mac'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StyleOption extends StatefulWidget {
  final String label;
  final String emoji;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _StyleOption({
    required this.label,
    required this.emoji,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_StyleOption> createState() => _StyleOptionState();
}

class _StyleOptionState extends State<_StyleOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.accent.withValues(alpha: isDarkTheme ? 0.14 : 0.09)
                : _hovered
                    ? AppColors.bgHover
                    : AppColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
            border: Border.all(
              color: widget.selected
                  ? AppColors.accent.withValues(alpha: isDarkTheme ? 0.45 : 0.5)
                  : _hovered
                      ? AppColors.borderHover
                      : AppColors.border,
              width: widget.selected ? 1.0 : 0.5,
            ),
            boxShadow: widget.selected && !isDarkTheme
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: AppTheme.inter(
                  fontSize: 12,
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                  color: widget.selected
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
              ),
              if (widget.selected) ...[
                const SizedBox(width: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Locale Picker ────────────────────────────────────────────

class _LocalePicker extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;
  const _LocalePicker({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.language, style: AppTheme.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _LangOption(code: 'fr', label: 'Français', flag: '🇫🇷', selected: current == 'fr', onTap: () => onChanged('fr'))),
              const SizedBox(width: 6),
              Expanded(child: _LangOption(code: 'en', label: 'English',  flag: '🇬🇧', selected: current == 'en', onTap: () => onChanged('en'))),
              const SizedBox(width: 6),
              Expanded(child: _LangOption(code: 'es', label: 'Español',  flag: '🇪🇸', selected: current == 'es', onTap: () => onChanged('es'))),
            ],
          ),
        ],
      ),
    );
  }
}

class _LangOption extends StatefulWidget {
  final String code, label, flag;
  final bool selected;
  final VoidCallback onTap;
  const _LangOption({required this.code, required this.label, required this.flag, required this.selected, required this.onTap});
  @override State<_LangOption> createState() => _LangOptionState();
}
class _LangOptionState extends State<_LangOption> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: widget.selected ? AppColors.accent.withValues(alpha: isDarkTheme ? 0.14 : 0.09) : _hovered ? AppColors.bgHover : AppColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
            border: Border.all(
              color: widget.selected ? AppColors.accent.withValues(alpha: 0.5) : _hovered ? AppColors.borderHover : AppColors.border,
              width: widget.selected ? 1.0 : 0.5,
            ),
          ),
          child: Column(
            children: [
              Text(widget.flag, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 2),
              Text(widget.label, style: AppTheme.inter(fontSize: 10, fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400, color: widget.selected ? AppColors.accent : AppColors.textSecondary), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Version / About tile ─────────────────────────────────────

class _VersionTile extends StatefulWidget {
  const _VersionTile();
  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final updateService = context.watch<UpdateService>();
    final version = updateService.currentVersion ?? '…';
    final notes = updateService.latestKnownNotes;
    final hasNotes = notes != null && notes.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Version row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text('🎛️', style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AudioRouter',
                      style: AppTheme.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${l10n.currentVersion} $version',
                      style: AppTheme.inter(fontSize: 10, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              // "What's new" toggle button
              if (hasNotes)
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _expanded
                            ? AppColors.accent.withValues(alpha: 0.12)
                            : AppColors.bgTertiary,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _expanded
                              ? AppColors.accent.withValues(alpha: 0.4)
                              : AppColors.border,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.whatsNew,
                            style: AppTheme.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: _expanded ? AppColors.accent : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _expanded ? FluentIcons.chevron_up : FluentIcons.chevron_down,
                            size: 8,
                            color: _expanded ? AppColors.accent : AppColors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: () => openUrl('https://github.com/DevOpenMindset/audio_router_releases/releases'),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(
                      l10n.seeChangelog,
                      style: AppTheme.inter(
                        fontSize: 10,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Expandable release notes
        if (_expanded && hasNotes)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgTertiary,
                borderRadius: BorderRadius.circular(AppColors.cardRadius),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: MarkdownBody(
                data: notes,
                styleSheet: MarkdownStyleSheet(
                  p: AppTheme.inter(fontSize: 11, color: AppColors.textSecondary, height: 1.5),
                  h2: AppTheme.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  h3: AppTheme.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  listBullet: AppTheme.inter(fontSize: 11, color: AppColors.textSecondary),
                  code: AppTheme.inter(fontSize: 10, color: AppColors.accent),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Setting Action Row (tappable, no toggle) ─────────────────

class _SettingAction extends StatefulWidget {
  final String label;
  final String description;
  final String icon;
  final VoidCallback onTap;

  const _SettingAction({
    required this.label,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_SettingAction> createState() => _SettingActionState();
}

class _SettingActionState extends State<_SettingAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: _isHovered ? AppColors.bgHover : Colors.transparent,
          child: Row(
            children: [
              Text(widget.icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: AppTheme.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.description,
                      style: AppTheme.inter(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                FluentIcons.chevron_right,
                size: 10,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

