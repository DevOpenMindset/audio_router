import 'dart:io';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:fluent_ui/fluent_ui.dart';

import 'package:macos_ui/macos_ui.dart' as macos;
import 'package:provider/provider.dart';
import '../platform.dart';
import '../theme/app_theme.dart';
import '../services/theme_service.dart';
import '../l10n/app_localizations.dart';

// ── URLs ────────────────────────────────────────────────────
const _paypalUrl = 'https://paypal.me/YOUR_PAYPAL_USERNAME';
const _coffeeUrl = 'https://buymeacoffee.com/YOUR_USERNAME';

/// Open a URL using the OS default handler (no extra dependency).
void _openUrl(String url) {
  if (Platform.isWindows) {
    Process.run('cmd', ['/c', 'start', '', url]);
  } else if (Platform.isMacOS) {
    Process.run('open', [url]);
  } else {
    Process.run('xdg-open', [url]);
  }
}

// ─── Public API ─────────────────────────────────────────────

/// Show the donation dialog (called from title bar, settings, or startup).
void showDonationDialog(BuildContext context) {
  if (isMacOS) {
    _showMacosDonation(context);
  } else {
    _showWindowsDonation(context);
  }
}

// ─── Windows / Fluent UI ────────────────────────────────────

void _showWindowsDonation(BuildContext context) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => const _WindowsDonationDialog(),
  );
}

class _WindowsDonationDialog extends StatelessWidget {
  const _WindowsDonationDialog();

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final l10n = context.l10n;
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
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    l10n.donateTitle,
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

            // Heart + body
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                children: [
                  // Animated heart
                  CustomPaint(
                    size: const Size(40, 36),
                    painter: _HeartPainter(color: AppColors.accent),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.donateBody,
                    textAlign: TextAlign.center,
                    style: AppTheme.inter(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            // Donation buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _DonateChip(
                      emoji: '💳',
                      label: l10n.donatePaypal,
                      onTap: () => _openUrl(_paypalUrl),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DonateChip(
                      emoji: '☕',
                      label: l10n.donateCoffee,
                      onTap: () => _openUrl(_coffeeUrl),
                    ),
                  ),
                ],
              ),
            ),

            // "Maybe later" subtle link
            Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 4),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(
                    l10n.maybeLater,
                    style: AppTheme.inter(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip-style donation button matching the _StyleOption pattern.
class _DonateChip extends StatefulWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _DonateChip({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  State<_DonateChip> createState() => _DonateChipState();
}

class _DonateChipState extends State<_DonateChip> {
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
            color: _hovered
                ? AppColors.accent.withValues(alpha: isDarkTheme ? 0.14 : 0.09)
                : AppColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
            border: Border.all(
              color: _hovered
                  ? AppColors.accent.withValues(alpha: isDarkTheme ? 0.45 : 0.5)
                  : AppColors.border,
              width: _hovered ? 1.0 : 0.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  style: AppTheme.inter(
                    fontSize: 12,
                    fontWeight: _hovered ? FontWeight.w600 : FontWeight.w400,
                    color: _hovered
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── macOS ──────────────────────────────────────────────────

void _showMacosDonation(BuildContext context) {
  final l10n = context.l10n;
  macos.showMacosAlertDialog<void>(
    context: context,
    builder: (ctx) => macos.MacosAlertDialog(
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
          CupertinoIcons.heart_fill,
          color: Color(0xFFFFFFFF),
          size: 32,
        ),
      ),
      title: Text(
        l10n.donateTitle,
        style: AppTheme.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      message: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Text(
            l10n.donateBody,
            textAlign: TextAlign.center,
            style: AppTheme.inter(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DonateChip(
                emoji: '💳',
                label: l10n.donatePaypal,
                onTap: () => _openUrl(_paypalUrl),
              ),
              const SizedBox(width: 8),
              _DonateChip(
                emoji: '☕',
                label: l10n.donateCoffee,
                onTap: () => _openUrl(_coffeeUrl),
              ),
            ],
          ),
        ],
      ),
      primaryButton: macos.PushButton(
        controlSize: macos.ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.pop(ctx),
        child: Text(l10n.maybeLater),
      ),
    ),
  );
}

// ─── Heart painter ──────────────────────────────────────────

class _HeartPainter extends CustomPainter {
  final Color color;
  const _HeartPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.5, h * 0.35)
      ..cubicTo(w * 0.5, h * 0.25, w * 0.37, 0, w * 0.18, 0)
      ..cubicTo(0, 0, 0, h * 0.25, 0, h * 0.25)
      ..cubicTo(0, h * 0.5, w * 0.18, h * 0.78, w * 0.5, h)
      ..cubicTo(w * 0.82, h * 0.78, w, h * 0.5, w, h * 0.25)
      ..cubicTo(w, h * 0.25, w, 0, w * 0.82, 0)
      ..cubicTo(w * 0.63, 0, w * 0.5, h * 0.25, w * 0.5, h * 0.35)
      ..close();

    canvas.drawPath(path, paint);

    // Subtle highlight
    final highlight = Paint()
      ..color = const Color(0x33FFFFFF)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(w * 0.3, h * 0.25),
      w * 0.08,
      highlight,
    );
  }

  @override
  bool shouldRepaint(_HeartPainter old) => old.color != color;
}
