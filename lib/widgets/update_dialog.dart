import 'dart:io';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:macos_ui/macos_ui.dart' as macos;
import 'package:provider/provider.dart';
import '../platform.dart';
import '../theme/app_theme.dart';
import '../services/theme_service.dart';
import '../services/update_service.dart';
import '../l10n/app_localizations.dart';

// ─── Shared ─────────────────────────────────────────────────

void _openUrl(String url) {
  if (Platform.isWindows) {
    Process.run('cmd', ['/c', 'start', '', url]);
  } else if (Platform.isMacOS) {
    Process.run('open', [url]);
  } else {
    Process.run('xdg-open', [url]);
  }
}

/// Show the auto-update UI if an update is available.
void showUpdateDialog(BuildContext context, UpdateInfo info) {
  if (isMacOS) {
    _showMacosUpdate(context, info);
  } else {
    _showWindowsUpdate(context, info);
  }
}

// ─── Windows / Fluent UI ────────────────────────────────────

void _showWindowsUpdate(BuildContext context, UpdateInfo updateInfo) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => _WindowsUpdateDialog(updateInfo: updateInfo),
  );
}

class _WindowsUpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  const _WindowsUpdateDialog({required this.updateInfo});

  @override
  State<_WindowsUpdateDialog> createState() => _WindowsUpdateDialogState();
}

class _WindowsUpdateDialogState extends State<_WindowsUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final l10n = context.l10n;
    final updateService = context.read<UpdateService>();

    return Center(
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          color: AppColors.bgSecondary,
          borderRadius: BorderRadius.circular(AppColors.dialogRadius),
          border: isDarkTheme
              ? Border.all(color: AppColors.border, width: 0.5)
              : null,
          boxShadow: AppColors.dialogShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(FluentIcons.cloud_download,
                      size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    '${l10n.updateAvailable} v${widget.updateInfo.version}',
                    style: AppTheme.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        FluentIcons.chrome_close,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: AppColors.border),

            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Text(
                l10n.updateBody,
                style: AppTheme.inter(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),

            // Action Area
            ..._buildActionArea(context, l10n, updateService),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActionArea(BuildContext context, AppLocalizations l10n, UpdateService updateService) {
    if (_isDownloading) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.downloading,
                style: AppTheme.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ProgressBar(value: _progress >= 0 ? _progress * 100 : null),
            ],
          ),
        ),
      ];
    }
    return [
      // Install / Download Button
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _PrimaryUpdateBtn(
          label: widget.updateInfo.assetDownloadUrl != null
              ? l10n.installUpdate
              : l10n.downloadUpdate,
          onTap: () {
            if (widget.updateInfo.assetDownloadUrl == null) {
              _openUrl(widget.updateInfo.releaseUrl);
              Navigator.pop(context);
              return;
            }
            setState(() {
              _isDownloading = true;
              _progress = 0.0;
            });
            updateService.downloadAndInstallUpdate(widget.updateInfo, (p) {
              if (!mounted) return;
              setState(() {
                if (p < 0) {
                  _isDownloading = false;
                } else {
                  _progress = p;
                }
              });
            });
          },
        ),
      ),

      // Skip / Later
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  l10n.maybeLater,
                  style: AppTheme.inter(fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 10, color: AppColors.border),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () async {
                await updateService.skipVersion(widget.updateInfo.version);
                if (context.mounted) Navigator.pop(context);
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  l10n.skipUpdate,
                  style: AppTheme.inter(fontSize: 11, color: AppColors.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

class _PrimaryUpdateBtn extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _PrimaryUpdateBtn({required this.label, required this.onTap});

  @override
  State<_PrimaryUpdateBtn> createState() => _PrimaryUpdateBtnState();
}

class _PrimaryUpdateBtnState extends State<_PrimaryUpdateBtn> {
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
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.accent : AppColors.accent.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
          ),
          child: Text(
            widget.label,
            style: AppTheme.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── macOS ──────────────────────────────────────────────────

void _showMacosUpdate(BuildContext context, UpdateInfo updateInfo) {

  macos.showMacosAlertDialog<void>(
    context: context,
    builder: (ctx) => _MacosUpdateDialog(updateInfo: updateInfo),
  );
}

class _MacosUpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  const _MacosUpdateDialog({required this.updateInfo});

  @override
  State<_MacosUpdateDialog> createState() => _MacosUpdateDialogState();
}

class _MacosUpdateDialogState extends State<_MacosUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final updateService = context.read<UpdateService>();

    return macos.MacosAlertDialog(
      appIcon: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          CupertinoIcons.cloud_download_fill,
          color: Color(0xFFFFFFFF),
          size: 32,
        ),
      ),
      title: Text(
        '${l10n.updateAvailable} v${widget.updateInfo.version}',
        style: AppTheme.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      message: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          if (_isDownloading) ...[
            Text(
              l10n.downloading,
              textAlign: TextAlign.center,
              style: AppTheme.inter(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            ProgressBar(value: _progress >= 0 ? _progress * 100 : null),
          ] else ...[
            Text(
              l10n.updateBody,
              textAlign: TextAlign.center,
              style: AppTheme.inter(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                await updateService.skipVersion(widget.updateInfo.version);
                if (context.mounted) Navigator.pop(context);
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  l10n.skipUpdate,
                  style: AppTheme.inter(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      primaryButton: macos.PushButton(
        controlSize: macos.ControlSize.large,
        onPressed: _isDownloading
            ? null
            : () {
                if (widget.updateInfo.assetDownloadUrl == null) {
                  _openUrl(widget.updateInfo.releaseUrl);
                  Navigator.pop(context);
                  return;
                }
                setState(() {
                  _isDownloading = true;
                  _progress = 0.0;
                });
                updateService.downloadAndInstallUpdate(widget.updateInfo, (p) {
                  if (!mounted) return;
                  setState(() {
                    if (p < 0) {
                      _isDownloading = false;
                    } else {
                      _progress = p;
                    }
                  });
                });
              },
        child: Text(
          widget.updateInfo.assetDownloadUrl != null
              ? l10n.installUpdate
              : l10n.downloadUpdate,
        ),
      ),
      secondaryButton: macos.PushButton(
        controlSize: macos.ControlSize.large,
        secondary: true,
        onPressed: _isDownloading ? null : () => Navigator.pop(context),
        child: Text(l10n.maybeLater),
      ),
    );
  }
}

