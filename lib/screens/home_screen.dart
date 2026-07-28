import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:macos_ui/macos_ui.dart' as macos;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import '../models/audio_models.dart';
import '../services/audio_service.dart';
import '../services/panel_controller.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import '../widgets/title_bar.dart';
import '../widgets/session_card.dart';
import '../widgets/device_footer.dart';
import '../widgets/duck_rules_panel.dart';
import '../widgets/app_rules_panel.dart';
import '../widgets/toast_notification.dart';
import '../widgets/macos_routing_banner.dart';
import '../widgets/donation_dialog.dart';
import '../widgets/update_dialog.dart';
import '../services/update_service.dart';
import '../l10n/app_localizations.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WindowListener {
  AudioService? _audioService;
  Timer? _saveWindowSizeTimer;
  int _tab = 0;
  late final macos.MacosTabController _macTabCtrl =
      macos.MacosTabController(length: 3, initialIndex: 0);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _macTabCtrl.addListener(() {
      if (_macTabCtrl.index != _tab) setState(() => _tab = _macTabCtrl.index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _audioService = context.read<AudioService>();
      _audioService!.onDevicesChanged = (added, removed) {
        if (!mounted) return;
        for (final d in added)   AudioToast.showConnected(context, d.shortName);
        for (final d in removed) AudioToast.showDisconnected(context, d.shortName);
      };
      Future.delayed(const Duration(milliseconds: 1500), () async {
        if (!mounted) return;
        final updateInfo = await context.read<UpdateService>().checkForUpdates();
        if (!mounted) return;
        if (updateInfo != null) showUpdateDialog(context, updateInfo);
        else showDonationDialog(context);
      });
      
      _audioService!.addListener(_syncColor);
      _syncColor();
    });
  }

  void _syncColor() {
    if (!mounted) return;
    final themeSvc = context.read<ThemeService>();
    if (themeSvc.useOSAccent && _audioService!.isNativeMode) {
      final osAccent = _audioService!.getAccentColor();
      if (osAccent != 0 && osAccent != themeSvc.accentColor?.value) {
        themeSvc.setAccentColor(Color(osAccent));
      }
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _saveWindowSizeTimer?.cancel();
    _macTabCtrl.dispose();
    if (_audioService != null) {
      _audioService!.removeListener(_syncColor);
      _audioService!.onDevicesChanged = null;
    }
    super.dispose();
  }

  @override
  void onWindowBlur() {
    // Panel behavior on macOS: losing focus closes the popover, like any
    // menu-bar panel. Routing keeps running — only the window hides.
    if (PanelController.enabled) PanelController.hideFromBlur();
  }

  @override
  void onWindowClose() async {
    // Native close button: window has setPreventClose(true), so hide to the
    // tray instead of quitting (Quit in the tray menu disables preventClose
    // first, in which case the window really closes and this must not hide).
    if (await windowManager.isPreventClose()) {
      _audioService?.resetAllRoutes();
      await windowManager.hide();
    }
  }

  @override
  void onWindowResize() {
    _saveWindowSizeTimer?.cancel();
    _saveWindowSizeTimer = Timer(const Duration(milliseconds: 500), () async {
      final size = await windowManager.getSize();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('window_width',  size.width);
      await prefs.setDouble('window_height', size.height);
    });
  }

  void _setTab(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    if (_macTabCtrl.index != i) _macTabCtrl.index = i;
  }

  // ─── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    return Platform.isMacOS ? _buildMacOS(context) : _buildWindows(context);
  }

  // ════════════════════════════════════════════════════════════
  // WINDOWS
  // ════════════════════════════════════════════════════════════

  Widget _buildWindows(BuildContext context) {
    final l10n = context.l10n;
    return ColoredBox(
      color: AppColors.bgPrimary,
      child: Column(
        children: [
          // ── Title bar + embedded pivot tabs ──────────────────
          Consumer<AudioService>(
            builder: (context, audioService, _) => CustomTitleBar(
              onClose: () { audioService.resetAllRoutes(); windowManager.hide(); },
              onMinimize: () => windowManager.minimize(),
              onDonate: () => showDonationDialog(context),
              onReset: () { audioService.resetAllRoutes(); audioService.clearRouteMemory(); },
              tabLabels: [l10n.appsTab, l10n.rulesTab, l10n.settingsTab],
              tabIcons: const [
                FluentIcons.speakers,
                FluentIcons.lightning_bolt,
                FluentIcons.settings,
              ],
              selectedTab: _tab,
              onTabChanged: _setTab,
            ),
          ),

          // ── Content ──────────────────────────────────────────
          Flexible(child: _tabContent(context, null)),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // macOS
  // ════════════════════════════════════════════════════════════

  Widget _buildMacOS(BuildContext context) {
    final audioService = context.read<AudioService>();
    final l10n = context.l10n;
    // On true macOS, use macos.MacosScaffold with native toolbar.
    // The custom _MacosTitleBar (with embedded tabs) handles the non-native case.
    return ColoredBox(
      color: AppColors.bgPrimary,
      child: macos.MacosScaffold(
        backgroundColor: AppColors.bgPrimary,
        toolBar: macos.ToolBar(
          height: 52,
          // The native title-bar buttons remain visible with
          // TitleBarStyle.hidden, so no custom traffic lights here — just a
          // draggable spacer that clears them. Close is handled by
          // onWindowClose below (window has setPreventClose(true)).
          leading: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => windowManager.startDragging(),
            child: const SizedBox(width: 70, height: double.infinity),
          ),
          title: _MacTabBar(
            tabs: [l10n.appsTab, l10n.rulesTab, l10n.settingsTab],
            icons: const [
              CupertinoIcons.speaker_2,
              CupertinoIcons.bolt,
              CupertinoIcons.settings,
            ],
            selected: _tab,
            onChanged: _setTab,
          ),
          // ToolBar clips its title to titleWidth (default 150), which cut the
          // third tab off outside the pill. Wide enough for all three tabs in
          // any supported language.
          titleWidth: 360,
          centerTitle: true,
          dividerColor: AppColors.border,
          actions: [
            macos.ToolBarIconButton(
              label: l10n.reset,
              icon: macos.MacosIcon(CupertinoIcons.arrow_counterclockwise, size: 16, color: AppColors.textSecondary),
              onPressed: () { audioService.resetAllRoutes(); audioService.clearRouteMemory(); },
              showLabel: false,
              tooltipMessage: l10n.resetTooltip,
            ),
            macos.ToolBarIconButton(
              label: l10n.supportProject,
              icon: macos.MacosIcon(CupertinoIcons.heart, size: 16, color: AppColors.textSecondary),
              onPressed: () => showDonationDialog(context),
              showLabel: false,
              tooltipMessage: l10n.supportProject,
            ),
          ],
        ),
        children: [
          macos.ContentArea(
            builder: (ctx, scrollController) => _tabContent(ctx, scrollController),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // TAB CONTENT (shared)
  // ════════════════════════════════════════════════════════════

  Widget _tabContent(BuildContext context, ScrollController? scrollCtrl) {
    switch (_tab) {
      case 1:  return _rulesTab(context, scrollCtrl);
      case 2:  return _settingsTab(context, scrollCtrl);
      default: return _appsTab(context, scrollCtrl);
    }
  }

  // ── Apps ─────────────────────────────────────────────────────

  Widget _appsTab(BuildContext context, ScrollController? scrollCtrl) {
    return Consumer<AudioService>(
      builder: (context, audio, _) {
        final sessions = audio.activeSessions;
        final deviceVolumesFold = Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _DeviceVolumesFold(
            devices: audio.devices,
            sessions: sessions,
            defaultDeviceId: audio.devices
                .where((d) => d.isDefault)
                .map((d) => d.id)
                .firstOrNull,
          ),
        );
        final child = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MacOsRoutingBanner(),
            if (sessions.isEmpty)
              _emptyState(context.l10n.noAudio)
            else
              ...sessions.map((session) {
                final device = audio.getDeviceForSession(session);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  // Keyed by display name (the grouping key) so state like the
                  // fetched app icon follows the session when the list reorders.
                  child: SessionCard(
                    key: ValueKey(session.displayName),
                    session: session,
                    devices: audio.devices,
                    assignedDevice: device,
                    mirrorDevices: audio.getMirrorDevicesForSession(session),
                    onDeviceChanged: (newDevice) {
                      final oldId = device?.id;
                      if (oldId != null && oldId != newDevice.id && session.mirrorDeviceIds.isNotEmpty) {
                        for (final mid in session.mirrorDeviceIds) {
                          audio.removeMirrorDevice(session.processId, oldId, mid);
                          if (mid != newDevice.id) audio.addMirrorDevice(session.processId, newDevice.id, mid);
                        }
                      }
                      audio.routeSession(session.processId, newDevice.id);
                    },
                    onMirrorAdded: (d) {
                      final pid = device?.id ?? audio.devices.firstWhere((d) => d.isDefault, orElse: () => audio.devices.first).id;
                      audio.addMirrorDevice(session.processId, pid, d.id);
                    },
                    onMirrorRemoved: (mid) {
                      final pid = device?.id ?? audio.devices.firstWhere((d) => d.isDefault, orElse: () => audio.devices.first).id;
                      audio.removeMirrorDevice(session.processId, pid, mid);
                    },
                    onVolumeChanged: (v) => audio.setSessionVolume(session.processId, v),
                    onMuteToggle:    ()  => audio.toggleMute(session.processId),
                  ),
                );
              }),
            deviceVolumesFold,
          ],
        );
        return _scroll(child, scrollCtrl);
      },
    );
  }

  // ── Rules ────────────────────────────────────────────────────

  Widget _rulesTab(BuildContext context, ScrollController? scrollCtrl) {
    return _scroll(
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppRulesPanel(),
          SizedBox(height: 16),
          DuckRulesPanel(),
        ],
      ),
      scrollCtrl,
    );
  }

  // ── Settings ─────────────────────────────────────────────────

  Widget _settingsTab(BuildContext context, ScrollController? scrollCtrl) {
    return Consumer<AudioService>(
      builder: (context, audio, _) => _scroll(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DeviceFooter(
              devices: audio.devices,
              sessions: audio.activeSessions,
              defaultDeviceId: audio.devices.where((d) => d.isDefault).map((d) => d.id).firstOrNull,
            ),
            const SizedBox(height: 12),
            const SettingsScreen(inline: true),
          ],
        ),
        scrollCtrl,
        topPadding: 8,
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────

  Widget _scroll(Widget child, ScrollController? ctrl, {double topPadding = 12}) {
    final padding = EdgeInsets.fromLTRB(12, topPadding, 12, 12);
    if (ctrl != null) {
      return macos.MacosScrollbar(
        controller: ctrl,
        child: SingleChildScrollView(controller: ctrl, padding: padding, child: child),
      );
    }
    return SingleChildScrollView(padding: padding, child: child);
  }

  Widget _emptyState(String label) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Text(label, style: AppTheme.inter(fontSize: 12, color: AppColors.textTertiary)),
    ),
  );
}

// ════════════════════════════════════════════════════════════════
// Collapsible device-volumes section (Apps tab)
// ════════════════════════════════════════════════════════════════

/// Folded-away access to each hardware device's system (master) volume from
/// the Apps tab, so it's reachable without switching to Settings. Collapsed
/// by default; the state persists across restarts.
class _DeviceVolumesFold extends StatefulWidget {
  final List<AudioDevice> devices;
  final List<AudioSession> sessions;
  final String? defaultDeviceId;

  const _DeviceVolumesFold({
    required this.devices,
    required this.sessions,
    this.defaultDeviceId,
  });

  @override
  State<_DeviceVolumesFold> createState() => _DeviceVolumesFoldState();
}

class _DeviceVolumesFoldState extends State<_DeviceVolumesFold> {
  static const _prefsKey = 'apps_tab_devices_expanded';
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getBool(_prefsKey) ?? false;
      if (mounted && saved != _expanded) setState(() => _expanded = saved);
    });
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_prefsKey, _expanded));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 0.5, color: AppColors.border),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? FluentIcons.chevron_down
                        : FluentIcons.chevron_right,
                    size: 8,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.audioOutputs,
                    style: AppTheme.inter(
                        fontSize: 11, color: AppColors.textTertiary),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.devices.where((d) => d.isActive).length}',
                    style: AppTheme.inter(
                        fontSize: 10, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          DeviceFooter(
            devices: widget.devices,
            sessions: widget.sessions,
            defaultDeviceId: widget.defaultDeviceId,
            showHeader: false,
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// macOS toolbar tabs (used inside true macOS MacosScaffold toolbar)
// ════════════════════════════════════════════════════════════════

// ════════════════════════════════════════════════════════════════
// macOS toolbar tabs — icon (CupertinoIcons) + label, native feel
// ════════════════════════════════════════════════════════════════

class _MacTabBar extends StatelessWidget {
  final List<String> tabs;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onChanged;

  const _MacTabBar({
    required this.tabs,
    required this.icons,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Center loosens the ToolBar title's tight width constraint (titleWidth)
    // so the pill hugs its tabs instead of stretching to the full title box.
    return Center(
      child: Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDarkTheme
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDarkTheme
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(tabs.length, (i) {
          final isLast = i == tabs.length - 1;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MacTabButton(
                label: tabs[i],
                icon: icons[i],
                selected: selected == i,
                onTap: () => onChanged(i),
              ),
              if (!isLast)
                Container(
                  width: 0.5,
                  height: 24,
                  color: isDarkTheme
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.08),
                ),
            ],
          );
        }),
      ),
      ),
    );
  }
}

class _MacTabButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _MacTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_MacTabButton> createState() => _MacTabButtonState();
}

class _MacTabButtonState extends State<_MacTabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.accent.withValues(alpha: isDarkTheme ? 0.22 : 0.12)
                : _hovered
                    ? (isDarkTheme
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04))
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              macos.MacosIcon(
                widget.icon,
                size: 16,
                color: widget.selected
                    ? AppColors.accent
                    : _hovered
                        ? AppColors.textSecondary
                        : AppColors.textTertiary,
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: AppTheme.inter(
                  fontSize: 10,
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                  color: widget.selected
                      ? AppColors.accent
                      : _hovered
                          ? AppColors.textSecondary
                          : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
