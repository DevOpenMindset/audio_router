import 'dart:io' show Platform;
import '../platform.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:macos_ui/macos_ui.dart' as macos;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../services/audio_service.dart';
import '../services/custom_name_service.dart';
import '../services/theme_service.dart';
import '../models/audio_models.dart';
import '../theme/app_theme.dart';
import '../widgets/title_bar.dart';
import '../widgets/session_card.dart';
import '../widgets/device_footer.dart';
import '../widgets/duck_rules_panel.dart';
import '../widgets/toast_notification.dart';
import '../widgets/macos_routing_banner.dart';
import '../widgets/adaptive_widgets.dart';
import '../widgets/donation_dialog.dart';
import '../l10n/app_localizations.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  // Keep a direct ref to unregister the callback on dispose
  AudioService? _audioService;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text);
    });

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

      // Startup donation popup — shown after a short delay.
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        showDonationDialog(context);
      });
    });
  }

  @override
  void dispose() {
    _audioService?.onDevicesChanged = null;
    _searchCtrl.dispose();
    super.dispose();
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

                  // Apply search filter (shown only when > 3 sessions)
                  final filtered = _searchQuery.isEmpty
                      ? active
                      : active
                          .where((s) {
                            final name = context
                                .read<CustomNameService>()
                                .nameFor(s.processName, s.displayName)
                                .toLowerCase();
                            return name.contains(_searchQuery.toLowerCase());
                          })
                          .toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // macOS < 14.2 limitation notice
                      const MacOsRoutingBanner(),

                      // ── Search bar (only when > 3 sessions) ──
                      if (active.length > 3) ...[
                        _SearchBar(controller: _searchCtrl),
                        const SizedBox(height: 8),
                      ],

                      // ── Session cards ─────────────────────────
                      ...filtered.map((session) {
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

                      // Empty state when search yields nothing
                      if (filtered.isEmpty && _searchQuery.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              context.l10n.noMatch,
                              style: AppTheme.inter(
                                fontSize: 12,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ),

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
                final filtered = _searchQuery.isEmpty
                    ? active
                    : active
                        .where((s) {
                          final name = ctx2
                              .read<CustomNameService>()
                              .nameFor(s.processName, s.displayName)
                              .toLowerCase();
                          return name.contains(_searchQuery.toLowerCase());
                        })
                        .toList();

                return macos.MacosScrollbar(
                  controller: scrollController,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const MacOsRoutingBanner(),

                        if (active.length > 3) ...[
                          macos.MacosSearchField(
                            placeholder: ctx2.l10n.search,
                            onChanged: (q) => setState(() => _searchQuery = q),
                          ),
                          const SizedBox(height: 8),
                        ],

                        ...filtered.map((session) {
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

                        if (filtered.isEmpty && _searchQuery.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                ctx2.l10n.noMatch,
                                style: AppTheme.inter(
                                  fontSize: 12,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ),

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

// ─── Search bar widget ──────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final l10n = context.l10n;
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          const SizedBox(width: 9),
          Text('🔍',
              style: AppTheme.inter(
                  fontSize: 11, color: AppColors.textTertiary)),
          const SizedBox(width: 6),
          Expanded(
            child: AdaptiveTextField(
              controller: controller,
              placeholder: l10n.search,
              style: AppTheme.inter(fontSize: 12, color: AppColors.textPrimary),
              placeholderStyle:
                  AppTheme.inter(fontSize: 12, color: AppColors.textTertiary),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: const BoxDecoration(),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: controller.clear,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('✕',
                    style: AppTheme.inter(
                        fontSize: 11, color: AppColors.textTertiary)),
              ),
            ),
        ],
      ),
    );
  }
}

