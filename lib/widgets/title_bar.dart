import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../platform.dart';
import '../theme/app_theme.dart';
import '../services/theme_service.dart';
import '../l10n/app_localizations.dart';


/// Platform-adaptive title bar — tabs are embedded directly inside.
/// Windows → Win11 caption buttons on the right, pivot tabs in the centre.
/// macOS   → Traffic-light circles on the left, tab buttons in the centre.
class CustomTitleBar extends StatelessWidget {
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onSettings;
  final VoidCallback? onReset;
  final VoidCallback? onDonate;

  // Embedded tab navigation
  final List<String> tabLabels;
  final List<IconData> tabIcons;
  final int selectedTab;
  final ValueChanged<int> onTabChanged;

  const CustomTitleBar({
    super.key,
    this.onClose,
    this.onMinimize,
    this.onSettings,
    this.onReset,
    this.onDonate,
    required this.tabLabels,
    required this.tabIcons,
    required this.selectedTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) return const SizedBox.shrink();
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: isMacOS
          ? _MacosTitleBar(
              onClose: onClose,
              onMinimize: onMinimize,
              onReset: onReset,
              onDonate: onDonate,
              tabLabels: tabLabels,
              tabIcons: tabIcons,
              selectedTab: selectedTab,
              onTabChanged: onTabChanged,
            )
          : _WindowsTitleBar(
              onClose: onClose,
              onMinimize: onMinimize,
              onReset: onReset,
              onDonate: onDonate,
              tabLabels: tabLabels,
              tabIcons: tabIcons,
              selectedTab: selectedTab,
              onTabChanged: onTabChanged,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Windows 11 title bar
// ─────────────────────────────────────────────────────────────

class _WindowsTitleBar extends StatelessWidget {
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onReset;
  final VoidCallback? onDonate;
  final List<String> tabLabels;
  final List<IconData> tabIcons;
  final int selectedTab;
  final ValueChanged<int> onTabChanged;

  const _WindowsTitleBar({
    this.onClose,
    this.onMinimize,
    this.onReset,
    this.onDonate,
    required this.tabLabels,
    required this.tabIcons,
    required this.selectedTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final l10n = context.l10n;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.bgPrimary,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // ── Logo + name ─────────────────────────────────────
          const SizedBox(width: 12),
          CustomPaint(size: const Size(13, 13), painter: _AppLogoPainter()),
          const SizedBox(width: 6),
          Text(
            l10n.appName,
            style: AppTheme.inter(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: AppColors.textTertiary,
              letterSpacing: -0.1,
            ),
          ),
          // ── Separator ───────────────────────────────────────
          Container(
            width: 0.5, height: 14, margin: const EdgeInsets.symmetric(horizontal: 10),
            color: AppColors.border,
          ),
          // ── Pivot tabs (icon + label + accent underline) ────
          ...List.generate(tabLabels.length, (i) => _WinTitleTab(
            label: tabLabels[i],
            icon: tabIcons[i],
            selected: selectedTab == i,
            onTap: () => onTabChanged(i),
          )),
          const Spacer(),
          // ── Utility buttons ─────────────────────────────────
          _WinUtilButton(
            onTap: onReset,
            tooltip: l10n.resetTooltip,
            child: CustomPaint(size: const Size(12, 12), painter: _ResetIconPainter()),
          ),
          _WinUtilButton(
            onTap: onDonate,
            tooltip: l10n.supportProject,
            child: CustomPaint(size: const Size(12, 11), painter: _HeartIconPainter()),
          ),
          const SizedBox(width: 4),
          // ── Win11 caption buttons ────────────────────────────
          _WinCaptionButton(
            onTap: onMinimize,
            isClose: false,
            child: Container(
              width: 10, height: 1.3,
              decoration: BoxDecoration(
                color: AppColors.textSecondary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          _WinCaptionButton(
            onTap: onClose,
            isClose: true,
            child: CustomPaint(
              size: const Size(10, 10),
              painter: _WinCloseIconPainter(hovered: false),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact pivot tab embedded in the Win title bar.
class _WinTitleTab extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _WinTitleTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  @override State<_WinTitleTab> createState() => _WinTitleTabState();
}

class _WinTitleTabState extends State<_WinTitleTab> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.selected
        ? AppColors.textPrimary
        : _hovered ? AppColors.textSecondary : AppColors.textTertiary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          height: double.infinity,
          decoration: BoxDecoration(
            color: _hovered && !widget.selected
                ? AppColors.bgHover
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: widget.selected ? AppColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13,
                  color: widget.selected ? AppColors.accent : color),
              const SizedBox(width: 5),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 140),
                style: AppTheme.inter(
                  fontSize: 12,
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small utility button (reset / settings) — 28 × 24, rounded.
class _WinUtilButton extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final String? tooltip;

  const _WinUtilButton({required this.child, this.onTap, this.tooltip});

  @override
  State<_WinUtilButton> createState() => _WinUtilButtonState();
}

class _WinUtilButtonState extends State<_WinUtilButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final btn = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 28,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: widget.child,
        ),
      ),
    );
    return widget.tooltip != null
        ? Tooltip(message: widget.tooltip!, child: btn)
        : btn;
  }
}

/// Win11 caption button — 46 × 32 (close) or 46 × 32 (minimize).
/// Close turns red (#C42B1C) on hover; minimize uses standard hover.
class _WinCaptionButton extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final bool isClose;

  const _WinCaptionButton({
    required this.child,
    this.onTap,
    required this.isClose,
  });

  @override
  State<_WinCaptionButton> createState() => _WinCaptionButtonState();
}

class _WinCaptionButtonState extends State<_WinCaptionButton> {
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
          duration: const Duration(milliseconds: 80),
          width: 46,
          height: 32,
          alignment: Alignment.center,
          color: _hovered
              ? (widget.isClose
                  ? const Color(0xFFC42B1C) // Win11 exact close-hover red
                  : isDarkTheme
                      ? const Color(0xFF404040)
                      : const Color(0xFFD8D8D8))
              : Colors.transparent,
          // Show white icon on close-hover, normal colour otherwise
          child: widget.isClose && _hovered
              ? CustomPaint(
                  size: const Size(10, 10),
                  painter: _WinCloseIconPainter(hovered: true),
                )
              : widget.child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// macOS title bar
// ─────────────────────────────────────────────────────────────

class _MacosTitleBar extends StatelessWidget {
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onReset;
  final VoidCallback? onDonate;
  final List<String> tabLabels;
  final List<IconData> tabIcons;
  final int selectedTab;
  final ValueChanged<int> onTabChanged;

  const _MacosTitleBar({
    this.onClose,
    this.onMinimize,
    this.onReset,
    this.onDonate,
    required this.tabLabels,
    required this.tabIcons,
    required this.selectedTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeService>();
    final l10n = context.l10n;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.bgPrimary,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Stack(
        children: [
          // ── Traffic lights (left) ──────────────────────────
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: MacosTrafficLights(
                  onClose: onClose,
                  onMinimize: onMinimize,
                ),
              ),
            ),
          ),
          // ── Tab buttons (centre) ───────────────────────────
          Center(
            child: _MacTabGroup(
              labels: tabLabels,
              icons: tabIcons,
              selected: selectedTab,
              onChanged: onTabChanged,
            ),
          ),
          // ── Action buttons (right) ────────────────────────
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MacosActionButton(
                      onTap: onReset,
                      tooltip: l10n.resetTooltip,
                      icon: CupertinoIcons.arrow_counterclockwise,
                    ),
                    const SizedBox(width: 2),
                    _MacosActionButton(
                      onTap: onDonate,
                      tooltip: l10n.supportProject,
                      icon: CupertinoIcons.heart,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented tab group for the macOS title bar.
class _MacTabGroup extends StatelessWidget {
  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onChanged;
  const _MacTabGroup({
    required this.labels,
    required this.icons,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: isDarkTheme
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isDarkTheme
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.07),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (i) {
          final isLast = i == labels.length - 1;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MacTabBtn(
                label: labels[i],
                icon: icons[i],
                selected: selected == i,
                onTap: () => onChanged(i),
              ),
              if (!isLast)
                Container(
                  width: 0.5, height: 16,
                  color: isDarkTheme
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.07),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _MacTabBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _MacTabBtn({
    required this.label, required this.icon,
    required this.selected, required this.onTap,
  });
  @override State<_MacTabBtn> createState() => _MacTabBtnState();
}

class _MacTabBtnState extends State<_MacTabBtn> {
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
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppColors.accent.withValues(alpha: isDarkTheme ? 0.22 : 0.13)
                : _hovered
                    ? (isDarkTheme
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04))
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon, size: 12,
                color: widget.selected ? AppColors.accent
                    : _hovered ? AppColors.textSecondary : AppColors.textTertiary,
              ),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: AppTheme.inter(
                  fontSize: 11,
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                  color: widget.selected ? AppColors.accent
                      : _hovered ? AppColors.textSecondary : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// macOS traffic-light cluster.
/// On hover the whole cluster reveals the ✕ / ─ glyph on each dot.
class MacosTrafficLights extends StatefulWidget {
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;

  const MacosTrafficLights({super.key, this.onClose, this.onMinimize});

  @override
  State<MacosTrafficLights> createState() => MacosTrafficLightsState();
}

class MacosTrafficLightsState extends State<MacosTrafficLights> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Red — close
          _TrafficDot(
            color: const Color(0xFFFF5F57),
            borderColor: const Color(0xFFE0443E),
            showGlyph: _hovered,
            glyph: '✕',
            glyphSize: 6,
            onTap: widget.onClose,
          ),
          const SizedBox(width: 6),
          // Yellow — minimize
          _TrafficDot(
            color: const Color(0xFFFEBC2E),
            borderColor: const Color(0xFFD4A012),
            showGlyph: _hovered,
            glyph: '−',
            glyphSize: 7,
            onTap: widget.onMinimize,
          ),
          const SizedBox(width: 6),
          // Green — (disabled / no-op for fixed-size window)
          _TrafficDot(
            color: const Color(0xFF28C840),
            borderColor: const Color(0xFF14AE2C),
            showGlyph: _hovered,
            glyph: '+',
            glyphSize: 6,
            onTap: null,
          ),
        ],
      ),
    );
  }
}

class _TrafficDot extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final bool showGlyph;
  final String glyph;
  final double glyphSize;
  final VoidCallback? onTap;

  const _TrafficDot({
    required this.color,
    required this.borderColor,
    required this.showGlyph,
    required this.glyph,
    required this.glyphSize,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: showGlyph
            ? Center(
                child: Text(
                  glyph,
                  style: TextStyle(
                    fontSize: glyphSize,
                    height: 1.0,
                    color: const Color(0x99000000),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// Small circular action button (reset / settings) on the macOS bar.
class _MacosActionButton extends StatefulWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final String? tooltip;

  const _MacosActionButton({required this.icon, this.onTap, this.tooltip});

  @override
  State<_MacosActionButton> createState() => _MacosActionButtonState();
}

class _MacosActionButtonState extends State<_MacosActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // Use a plain flutter Tooltip (no FluentTheme dependency) so this widget
    // renders correctly inside both FluentApp and MacosApp.
    final btn = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered
                ? (isDarkTheme
                    ? const Color(0xFF424242)
                    : const Color(0xFFDDDDDD))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            widget.icon,
            size: 12,
            color: _hovered ? AppColors.textSecondary : AppColors.textTertiary,
          ),
        ),
      ),
    );
    // Use flutter's own Tooltip (from widgets.dart, no theme ancestor needed)
    // rather than fluent_ui's Tooltip so this works inside MacosApp too.
    if (widget.tooltip != null) {
      return _PlainTooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}

/// Minimal tooltip that works without any theme ancestor (FluentTheme or
/// Material).  Shown as a small dark bubble above the child.
class _PlainTooltip extends StatefulWidget {
  final String message;
  final Widget child;
  const _PlainTooltip({required this.message, required this.child});

  @override
  State<_PlainTooltip> createState() => _PlainTooltipState();
}

class _PlainTooltipState extends State<_PlainTooltip> {
  OverlayEntry? _entry;

  void _show(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    _entry = OverlayEntry(
      builder: (_) => Positioned(
        left: pos.dx,
        top: pos.dy - 28,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDarkTheme
                  ? const Color(0xFF303030)
                  : const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.message,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFEEEEEE),
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _show(context),
      onExit: (_) => _hide(),
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shared icon painters
// ─────────────────────────────────────────────────────────────

class _AppLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    paint.style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - 4, cy), 1.5, paint);
    paint.style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - 2, cy), Offset(cx + 1, cy - 3), paint);
    canvas.drawLine(Offset(cx - 2, cy), Offset(cx + 1, cy + 3), paint);
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx + 3, cy - 3), 1.2, paint);
    canvas.drawCircle(Offset(cx + 3, cy + 3), 1.2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}


class _ResetIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textTertiary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.38;

    // Arc ~270°
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -math.pi / 2,
      math.pi * 1.5,
      false,
      paint,
    );
    // Arrowhead at end of arc
    paint.style = PaintingStyle.fill;
    final arrowTip = Offset(cx, cy - r);
    canvas.drawPath(
      Path()
        ..moveTo(arrowTip.dx, arrowTip.dy - 2.5)
        ..lineTo(arrowTip.dx + 2.5, arrowTip.dy + 1)
        ..lineTo(arrowTip.dx - 2.5, arrowTip.dy + 1)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Win11 close ✕ — white when hovered (button is red), tertiary otherwise.
class _WinCloseIconPainter extends CustomPainter {
  final bool hovered;
  const _WinCloseIconPainter({required this.hovered});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = hovered ? const Color(0xFFFFFFFF) : AppColors.textSecondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(const Offset(0, 0), Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_WinCloseIconPainter old) => old.hovered != hovered;
}

/// Small heart icon for the title bar donation button.
class _HeartIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textTertiary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.5, h * 0.35)
      ..cubicTo(w * 0.5, h * 0.22, w * 0.37, 0, w * 0.2, 0)
      ..cubicTo(0, 0, 0, h * 0.28, 0, h * 0.28)
      ..cubicTo(0, h * 0.52, w * 0.2, h * 0.78, w * 0.5, h)
      ..cubicTo(w * 0.8, h * 0.78, w, h * 0.52, w, h * 0.28)
      ..cubicTo(w, h * 0.28, w, 0, w * 0.8, 0)
      ..cubicTo(w * 0.63, 0, w * 0.5, h * 0.22, w * 0.5, h * 0.35)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
