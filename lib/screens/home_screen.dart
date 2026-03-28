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
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WindowListener {
  // Keep a direct ref to unregister the callback on dispose
  AudioService? _audioService;
  Timer? _saveWindowSizeTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // Register device change callback after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _audioService = context.read<AudioService>();
      _audioService!.onDevicesChanged = (added, removed) {
        if (!mounted) return;
        for (final d in added) {
          AudioToast.showConnected(context, d.shortName);
        }
        for (final d in removed) {
          AudioToast.showDisconnected(context, d.shortName);
        }
      };

      // Startup update check + donation popup (shown after delay)
      Future.delayed(const Duration(milliseconds: 1500), () async {
        if (!mounted) return;
        
        final updateService = context.read<UpdateService>();
        final updateInfo = await updateService.checkForUpdates();
        
        if (!mounted) return;
        
        if (updateInfo != null) {
          // If update is available, show update dialog instead of donation
          showUpdateDialog(context, updateInfo);
        } else {
          // No update, fallback to donation popup
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

  // Save window size with a debounce so we don't hammer SharedPreferences
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

  // ─── Dialogs ────────────────────────────────────────────

  void _showSettingsDialog(BuildContext context) {
    if (Platform.isMacOS) {
      macos.showMacosSheet<void>(
        context: context,
        builder: (_) => macos.MacosSheet(
          insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: const SettingsScreen(),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (ctx) => const SettingsScreen(),
    );
  }

  // ─── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();

    // MacosScaffold/ToolBar use native vibrancy → transparent on Windows.
    // Use column layout on Windows always; MacosScaffold only on real macOS.
    if (Platform.isMacOS) return _buildMacOS(context);

    return ColoredBox(
      color: AppColors.bgPrimary,
      child: Column(
        children: [
          // Title bar
          Consumer<AudioService>(
            builder: (context, audioService, _) => CustomTitleBar(
              onClose: () {
                audioService.resetAllRoutes();
                windowManager.hide();
              },
              onMinimize: () => windowManager.minimize(),
              onSettings: () => _showSettingsDialog(context),
              onDonate: () => showDonationDialog(context),
              onReset: () {
                audioService.resetAllRoutes();
                audioService.clearRouteMemory();
              },
            ),
          ),

          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Consumer<AudioService>(
                builder: (context, audioService, _) {
                  final active = audioService.activeSessions;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // macOS < 14.2 limitation notice
                      const MacOsRoutingBanner(),

                      // ── Session cards ─────────────────────────
                      ...active.map((session) {
                        final device =
                            audioService.getDeviceForSession(session);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: SessionCard(
                            session: session,
                            devices: audioService.devices,
                            assignedDevice: device,
                            mirrorDevices: audioService
                                .getMirrorDevicesForSession(session),
                            onDeviceChanged: (newDevice) {
                              // If primary device changes, stop existing mirrors
                              // and restart them from the new primary.
                              // SAFETY: filter out newDevice.id from mirrors to
                              // prevent self-mirror (A→A) and echo loops.
                              final oldId = device?.id;
                              if (oldId != null &&
                                  oldId != newDevice.id &&
                                  session.mirrorDeviceIds.isNotEmpty) {
                                for (final mirrorId
                                    in session.mirrorDeviceIds) {
                                  audioService.removeMirrorDevice(
                                      session.processId, oldId, mirrorId);
                                  // Never re-add a mirror that equals the new primary
                                  if (mirrorId != newDevice.id) {
                                    audioService.addMirrorDevice(
                                        session.processId, newDevice.id, mirrorId);
                                  }
                                }
                              }
                              audioService.routeSession(
                                  session.processId, newDevice.id);
                            },
                            onMirrorAdded: (mirrorDevice) {
                              final primaryId = device?.id ??
                                  audioService.devices
                                      .firstWhere((d) => d.isDefault,
                                          orElse: () =>
                                              audioService.devices.first)
                                      .id;
                              audioService.addMirrorDevice(
                                  session.processId, primaryId, mirrorDevice.id);
                            },
                            onMirrorRemoved: (mirrorDeviceId) {
                              final primaryId = device?.id ??
                                  audioService.devices
                                      .firstWhere((d) => d.isDefault,
                                          orElse: () =>
                                              audioService.devices.first)
                                      .id;
                              audioService.removeMirrorDevice(
                                  session.processId, primaryId, mirrorDeviceId);
                            },
                            onVolumeChanged: (vol) {
                              audioService.setSessionVolume(
                                  session.processId, vol);
                            },
                            onMuteToggle: () {
                              audioService.toggleMute(session.processId);
                            },
                          ),
                        );
                      }),

                      // ── App rules ─────────────────────────────
                      const SizedBox(height: 12),
                      const AppRulesPanel(),

                      // ── Duck rules ────────────────────────────
                      const SizedBox(height: 12),
                      const DuckRulesPanel(),

                      // ── Device footer ─────────────────────────
                      const SizedBox(height: 12),
                      DeviceFooter(
                        devices: audioService.devices,
                        sessions: audioService.activeSessions,
                        defaultDeviceId: audioService.devices
                            .where((d) => d.isDefault)
                            .map((d) => d.id)
                            .firstOrNull,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
  // ─── macOS Build ────────────────────────────────────────────

  Widget _buildMacOS(BuildContext context) {
    final audioService = context.read<AudioService>();

    // ColoredBox + explicit backgroundColor everywhere to prevent the native
    // macOS vibrancy from showing through as transparent on Windows.
    return ColoredBox(
      color: AppColors.bgPrimary,
      child: macos.MacosScaffold(
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
          style: AppTheme.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        centerTitle: true,
        dividerColor: AppColors.border,
        actions: [
          macos.ToolBarIconButton(
            label: context.l10n.reset,
            icon: macos.MacosIcon(
              CupertinoIcons.arrow_counterclockwise,
              size: 16,
              color: AppColors.textSecondary,
            ),
            onPressed: () {
              audioService.resetAllRoutes();
              audioService.clearRouteMemory();
            },
            showLabel: false,
            tooltipMessage: context.l10n.resetTooltip,
          ),
          macos.ToolBarIconButton(
            label: context.l10n.supportProject,
            icon: macos.MacosIcon(
              CupertinoIcons.heart,
              size: 16,
              color: AppColors.textSecondary,
            ),
            onPressed: () => showDonationDialog(context),
            showLabel: false,
            tooltipMessage: context.l10n.supportProject,
          ),
          macos.ToolBarIconButton(
            label: context.l10n.settings,
            icon: macos.MacosIcon(
              CupertinoIcons.gear,
              size: 16,
              color: AppColors.textSecondary,
            ),
            onPressed: () => _showSettingsDialog(context),
            showLabel: false,
            tooltipMessage: context.l10n.settings,
          ),
        ],
      ),
      children: [
        macos.ContentArea(
          builder: (ctx, scrollController) {
            return Consumer<AudioService>(
              builder: (ctx2, audio, _) {
                final active = audio.activeSessions;

                return macos.MacosScrollbar(
                  controller: scrollController,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const MacOsRoutingBanner(),

                        ...active.map((session) {
                          final device = audio.getDeviceForSession(session);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: SessionCard(
                              session: session,
                              devices: audio.devices,
                              assignedDevice: device,
                              onDeviceChanged: (d) => audio.routeSession(session.processId, d.id),
                              onVolumeChanged: (v) => audio.setSessionVolume(session.processId, v),
                              onMuteToggle: () => audio.toggleMute(session.processId),
                            ),
                          );
                        }),

                        const SizedBox(height: 12),
                        const DuckRulesPanel(),
                        const SizedBox(height: 12),
                        DeviceFooter(
                          devices: audio.devices,
                          sessions: audio.activeSessions,
                          defaultDeviceId: audio.devices
                              .where((d) => d.isDefault)
                              .map((d) => d.id)
                              .firstOrNull,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
      ), // MacosScaffold
    ); // ColoredBox
  }
}


