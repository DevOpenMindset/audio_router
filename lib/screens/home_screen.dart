import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:macos_ui/macos_ui.dart' as macos;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import '../services/audio_service.dart';
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
import '../platform.dart' as _plat;
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WindowListener {
  AudioService? _audioService;
  Timer? _saveWindowSizeTimer;
  int _tab = 0; // 0 = Apps, 1 = Rules, 2 = Settings

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
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
        final updateService = context.read<UpdateService>();
        final updateInfo = await updateService.checkForUpdates();
        if (!mounted) return;
        if (updateInfo != null) {
          showUpdateDialog(context, updateInfo);
        } else {
          showDonationDialog(context);
        }
      });
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _saveWindowSizeTimer?.cancel();
    _audioService?.onDevicesChanged = null;
    super.dispose();
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

  // ─── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    if (Platform.isMacOS) return _buildMacOS(context);
    return _buildWindows(context);
  }

  // ─── Windows ────────────────────────────────────────────────

  Widget _buildWindows(BuildContext context) {
    return ColoredBox(
      color: AppColors.bgPrimary,
      child: Column(
        children: [
          // Title bar (no gear icon — settings is now a tab)
          Consumer<AudioService>(
            builder: (context, audioService, _) => CustomTitleBar(
              onClose: () {
                audioService.resetAllRoutes();
                windowManager.hide();
              },
              onMinimize: () => windowManager.minimize(),
              onSettings: null, // handled by tab
              onDonate: () => showDonationDialog(context),
              onReset: () {
                audioService.resetAllRoutes();
                audioService.clearRouteMemory();
              },
            ),
          ),

          // Tab content
          Flexible(child: _buildTabContent(context)),

          // Bottom tab bar
          _BottomTabBar(
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(BuildContext context) {
    switch (_tab) {
      case 1:  return _buildRulesTab(context);
      case 2:  return _buildSettingsTab(context);
      default: return _buildAppsTab(context);
    }
  }

  // ── Tab 0: Apps ──────────────────────────────────────────────

  Widget _buildAppsTab(BuildContext context) {
    return Consumer<AudioService>(
      builder: (context, audioService, _) {
        final active = audioService.activeSessions;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MacOsRoutingBanner(),
              if (active.isEmpty)
                _EmptyState(label: context.l10n.noAudio)
              else
                ...active.map((session) {
                  final device = audioService.getDeviceForSession(session);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SessionCard(
                      session: session,
                      devices: audioService.devices,
                      assignedDevice: device,
                      mirrorDevices: audioService.getMirrorDevicesForSession(session),
                      onDeviceChanged: (newDevice) {
                        final oldId = device?.id;
                        if (oldId != null && oldId != newDevice.id && session.mirrorDeviceIds.isNotEmpty) {
                          for (final mirrorId in session.mirrorDeviceIds) {
                            audioService.removeMirrorDevice(session.processId, oldId, mirrorId);
                            if (mirrorId != newDevice.id) {
                              audioService.addMirrorDevice(session.processId, newDevice.id, mirrorId);
                            }
                          }
                        }
                        audioService.routeSession(session.processId, newDevice.id);
                      },
                      onMirrorAdded: (mirrorDevice) {
                        final primaryId = device?.id ??
                            audioService.devices.firstWhere((d) => d.isDefault,
                                orElse: () => audioService.devices.first).id;
                        audioService.addMirrorDevice(session.processId, primaryId, mirrorDevice.id);
                      },
                      onMirrorRemoved: (mirrorDeviceId) {
                        final primaryId = device?.id ??
                            audioService.devices.firstWhere((d) => d.isDefault,
                                orElse: () => audioService.devices.first).id;
                        audioService.removeMirrorDevice(session.processId, primaryId, mirrorDeviceId);
                      },
                      onVolumeChanged: (vol) => audioService.setSessionVolume(session.processId, vol),
                      onMuteToggle: () => audioService.toggleMute(session.processId),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  // ── Tab 1: Rules ─────────────────────────────────────────────

  Widget _buildRulesTab(BuildContext context) {
    return Consumer<AudioService>(
      builder: (context, audioService, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppRulesPanel(),
              const SizedBox(height: 16),
              const DuckRulesPanel(),
            ],
          ),
        );
      },
    );
  }

  // ── Tab 2: Settings ──────────────────────────────────────────

  Widget _buildSettingsTab(BuildContext context) {
    return Consumer<AudioService>(
      builder: (context, audioService, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device master volumes at the top
              DeviceFooter(
                devices: audioService.devices,
                sessions: audioService.activeSessions,
                defaultDeviceId: audioService.devices
                    .where((d) => d.isDefault)
                    .map((d) => d.id)
                    .firstOrNull,
              ),
              const SizedBox(height: 12),
              // All settings inline
              const SettingsScreen(inline: true),
            ],
          ),
        );
      },
    );
  }

  // ─── macOS ──────────────────────────────────────────────────

  Widget _buildMacOS(BuildContext context) {
    final audioService = context.read<AudioService>();
    return ColoredBox(
      color: AppColors.bgPrimary,
      child: Column(
        children: [
          macos.MacosScaffold(
            backgroundColor: AppColors.bgPrimary,
            toolBar: macos.ToolBar(
              height: 40,
              leading: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: MacosTrafficLights(
                    onClose: () async {
                      audioService.resetAllRoutes();
                      await windowManager.hide();
                    },
                    onMinimize: () => windowManager.minimize(),
                  ),
                ),
              ),
              title: Text(
                context.l10n.appName,
                style: AppTheme.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
              ),
              centerTitle: true,
              dividerColor: AppColors.border,
              actions: [
                macos.ToolBarIconButton(
                  label: context.l10n.reset,
                  icon: macos.MacosIcon(CupertinoIcons.arrow_counterclockwise, size: 16, color: AppColors.textSecondary),
                  onPressed: () {
                    audioService.resetAllRoutes();
                    audioService.clearRouteMemory();
                  },
                  showLabel: false,
                  tooltipMessage: context.l10n.resetTooltip,
                ),
                macos.ToolBarIconButton(
                  label: context.l10n.supportProject,
                  icon: macos.MacosIcon(CupertinoIcons.heart, size: 16, color: AppColors.textSecondary),
                  onPressed: () => showDonationDialog(context),
                  showLabel: false,
                  tooltipMessage: context.l10n.supportProject,
                ),
              ],
            ),
            children: [
              macos.ContentArea(
                builder: (ctx, scrollController) => _buildMacOSTabContent(ctx, scrollController),
              ),
            ],
          ).expand(),

          // Bottom tab bar (same for both platforms)
          _BottomTabBar(
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ],
      ),
    );
  }

  Widget _buildMacOSTabContent(BuildContext context, ScrollController scrollController) {
    final audio = context.read<AudioService>();
    switch (_tab) {
      case 1:
        return macos.MacosScrollbar(
          controller: scrollController,
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(12),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppRulesPanel(),
                SizedBox(height: 16),
                DuckRulesPanel(),
              ],
            ),
          ),
        );
      case 2:
        return macos.MacosScrollbar(
          controller: scrollController,
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Consumer<AudioService>(
              builder: (ctx, audioService, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DeviceFooter(
                    devices: audioService.devices,
                    sessions: audioService.activeSessions,
                    defaultDeviceId: audioService.devices
                        .where((d) => d.isDefault)
                        .map((d) => d.id)
                        .firstOrNull,
                  ),
                  const SizedBox(height: 12),
                  const SettingsScreen(inline: true),
                ],
              ),
            ),
          ),
        );
      default:
        return Consumer<AudioService>(
          builder: (ctx2, audio2, _) {
            final active = audio2.activeSessions;
            return macos.MacosScrollbar(
              controller: scrollController,
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MacOsRoutingBanner(),
                    if (active.isEmpty)
                      _EmptyState(label: context.l10n.noAudio)
                    else
                      ...active.map((session) {
                        final device = audio2.getDeviceForSession(session);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: SessionCard(
                            session: session,
                            devices: audio2.devices,
                            assignedDevice: device,
                            onDeviceChanged: (d) => audio2.routeSession(session.processId, d.id),
                            onVolumeChanged: (v) => audio2.setSessionVolume(session.processId, v),
                            onMuteToggle: () => audio2.toggleMute(session.processId),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            );
          },
        );
    }
  }
}

// ─── Bottom Tab Bar ──────────────────────────────────────────

class _BottomTabBar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const _BottomTabBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final l10n = context.l10n;
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          _Tab(icon: '🎵', label: l10n.appsTab,     index: 0, selected: selected, onTap: onChanged),
          _Tab(icon: '⚡', label: l10n.rulesTab,    index: 1, selected: selected, onTap: onChanged),
          _Tab(icon: '⚙️', label: l10n.settingsTab, index: 2, selected: selected, onTap: onChanged),
        ],
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  final String icon;
  final String label;
  final int index;
  final int selected;
  final ValueChanged<int> onTap;
  const _Tab({required this.icon, required this.label, required this.index, required this.selected, required this.onTap});

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.index == widget.selected;
    final color = isSelected ? AppColors.accent : (_hovered ? AppColors.textSecondary : AppColors.textTertiary);

    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => widget.onTap(widget.index),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: _hovered && !isSelected ? AppColors.bgHover : Colors.transparent,
              border: Border(
                top: BorderSide(
                  color: isSelected ? AppColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(widget.icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  widget.label,
                  style: AppTheme.inter(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Empty State ─────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String label;
  const _EmptyState({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          label,
          style: AppTheme.inter(fontSize: 12, color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

// Extension so MacosScaffold can be used inside a Column
extension _WidgetExpand on Widget {
  Widget expand() => Expanded(child: this);
}
