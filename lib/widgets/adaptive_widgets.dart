import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:macos_ui/macos_ui.dart' as macos;
import '../platform.dart' as _plat;
import '../theme/app_theme.dart';

// ── Widget framework check: uses the STYLE-AWARE platform flag so that when
// the user picks the macOS style on Windows, all adaptive widgets (switches,
// sliders, dropdowns, dialogs…) use the macos_ui implementations.
// MacosTheme + MacosWindow are injected via FluentApp.builder in main.dart, so
// every macos_ui widget finds the required ancestor regardless of hardware.
bool get _onMacOS => _plat.isMacOS;
bool get _onLinux => _plat.isLinux;

// ─── Icon helpers (runtime, not const) ───────────────────────

IconData adaptiveCloseIcon() =>
    _onMacOS ? CupertinoIcons.xmark : fluent.FluentIcons.chrome_close;

IconData adaptiveUploadIcon() =>
    _onMacOS ? CupertinoIcons.arrow_up_to_line : fluent.FluentIcons.cloud_upload;

IconData adaptiveDownloadIcon() =>
    _onMacOS ? CupertinoIcons.arrow_down_to_line : fluent.FluentIcons.cloud_download;

// ─── Button ──────────────────────────────────────────────────

class AdaptiveButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool isSmall;

  const AdaptiveButton({
    super.key, 
    required this.onPressed, 
    required this.child,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    if (_onMacOS) {
      return macos.PushButton(
        controlSize: isSmall ? macos.ControlSize.small : macos.ControlSize.regular,
        secondary: true,
        onPressed: onPressed,
        child: DefaultTextStyle(
          style: TextStyle(
            fontSize: isSmall ? 11 : 13,
            fontWeight: FontWeight.w500,
            color: isDarkTheme ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
          ),
          child: child,
        ),
      );
    }
    if (_onLinux) {
      return material.OutlinedButton(
        onPressed: onPressed,
        style: material.OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: EdgeInsets.symmetric(horizontal: isSmall ? 10 : 16, vertical: isSmall ? 6 : 10),
          textStyle: TextStyle(fontSize: isSmall ? 12 : 14, fontWeight: FontWeight.w400),
        ),
        child: child,
      );
    }
    return fluent.Button(
      onPressed: onPressed, 
      child: DefaultTextStyle(
        style: TextStyle(
          fontSize: isSmall ? 12 : 14,
          fontWeight: FontWeight.w400,
        ),
        child: child,
      ),
    );
  }
}

class AdaptivePrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool isSmall;

  const AdaptivePrimaryButton({
    super.key, 
    required this.onPressed, 
    required this.child,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    if (_onMacOS) {
      return macos.PushButton(
        controlSize: isSmall ? macos.ControlSize.small : macos.ControlSize.regular,
        onPressed: onPressed,
        child: DefaultTextStyle(
          style: TextStyle(
            fontSize: isSmall ? 11 : 13,
            fontWeight: FontWeight.w600,
            color: isDarkTheme ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
          ),
          child: child,
        ),
      );
    }
    if (_onLinux) {
      return material.ElevatedButton(
        onPressed: onPressed,
        style: material.ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: material.Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: EdgeInsets.symmetric(horizontal: isSmall ? 10 : 16, vertical: isSmall ? 6 : 10),
          textStyle: TextStyle(fontSize: isSmall ? 12 : 14, fontWeight: FontWeight.w500),
        ),
        child: child,
      );
    }
    return fluent.FilledButton(
      onPressed: onPressed,
      child: DefaultTextStyle(
        style: TextStyle(
          fontSize: isSmall ? 12 : 14,
          fontWeight: FontWeight.w500,
          color: const Color(0xFFFFFFFF),
        ),
        child: child,
      ),
    );
  }
}

// ─── Text Field ──────────────────────────────────────────────

class AdaptiveTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final TextStyle? style;
  final TextStyle? placeholderStyle;
  final EdgeInsets padding;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  /// null = use default platform decoration.
  /// BoxDecoration() = transparent/bare (for inline rename fields).
  final BoxDecoration? decoration;

  const AdaptiveTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.style,
    this.placeholderStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style ?? TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: isDarkTheme ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
    );
    final resolvedPlaceholderStyle = placeholderStyle ?? TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: AppColors.textTertiary,
    );

    if (_onMacOS) {
      return macos.MacosTextField(
        controller: controller,
        focusNode: focusNode,
        placeholder: placeholder,
        style: resolvedStyle,
        placeholderStyle: resolvedPlaceholderStyle,
        padding: padding,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        autofocus: autofocus,
        decoration: decoration,
      );
    }
    if (_onLinux) {
      return material.TextField(
        controller: controller,
        focusNode: focusNode,
        style: resolvedStyle,
        autofocus: autofocus,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        decoration: material.InputDecoration(
          hintText: placeholder,
          hintStyle: resolvedPlaceholderStyle,
          contentPadding: padding,
          isDense: true,
          border: material.OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: material.OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: material.OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.accent, width: 2),
          ),
          filled: true,
          fillColor: AppColors.bgTertiary,
        ),
      );
    }
    return fluent.TextBox(
      controller: controller,
      focusNode: focusNode,
      placeholder: placeholder,
      placeholderStyle: resolvedPlaceholderStyle,
      style: resolvedStyle,
      padding: padding,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      autofocus: autofocus,
      // fluent TextBox.decoration est WidgetStateProperty<BoxDecoration>?
      decoration: decoration != null
          ? WidgetStateProperty.all(decoration!)
          : null,
    );
  }
}

// ─── Slider ──────────────────────────────────────────────────

class AdaptiveSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final Color? activeColor;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  const AdaptiveSlider({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.activeColor,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = activeColor ?? AppColors.accent;

    if (_onMacOS) {
      return macos.MacosSlider(
        value: value,
        min: min,
        max: max,
        onChanged: onChanged ?? (_) {},
        color: macos.MacosColor(effectiveColor.toARGB32()),
      );
    }
    if (_onLinux) {
      return material.SliderTheme(
        data: material.SliderThemeData(
          activeTrackColor: effectiveColor,
          inactiveTrackColor: AppColors.bgTertiary,
          thumbColor: isDarkTheme ? material.Colors.white : effectiveColor,
          overlayColor: effectiveColor.withValues(alpha: 0.12),
          trackHeight: 4,
        ),
        child: material.Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      );
    }
    return fluent.SliderTheme(
      data: fluent.SliderThemeData(
        useThumbBall: true,
        activeColor: fluent.WidgetStateProperty.all(effectiveColor),
      ),
      child: fluent.Slider(
        value: value,
        min: min,
        max: max,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
        vertical: false,
      ),
    );
  }
}

// ─── Toggle Switch ───────────────────────────────────────────

class AdaptiveToggle extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool>? onChanged;

  const AdaptiveToggle({super.key, required this.checked, this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (_onMacOS) {
      return macos.MacosSwitch(
        value: checked,
        onChanged: onChanged,
        activeColor: macos.MacosColor(AppColors.accent.toARGB32()),
      );
    }
    if (_onLinux) {
      return material.Switch(
        value: checked,
        onChanged: onChanged,
        activeColor: AppColors.accent,
        activeTrackColor: AppColors.accent.withValues(alpha: 0.5),
        inactiveThumbColor: AppColors.textTertiary,
        inactiveTrackColor: AppColors.bgTertiary,
      );
    }
    return fluent.ToggleSwitch(checked: checked, onChanged: onChanged);
  }
}

// ─── ComboBox / PopupButton ──────────────────────────────────

class AdaptiveComboBox<T> extends StatelessWidget {
  final T? value;
  final List<AdaptiveMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;
  final TextStyle? style;

  const AdaptiveComboBox({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.isExpanded = false,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (_onMacOS) {
      return macos.MacosPopupButton<T>(
        value: value,
        items: items
            .map((i) => macos.MacosPopupMenuItem<T>(value: i.value, child: i.child))
            .toList(),
        onChanged: onChanged,
      );
    }
    if (_onLinux) {
      return material.DropdownButton<T>(
        value: value,
        isExpanded: isExpanded,
        style: style ?? TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
        ),
        dropdownColor: AppColors.bgSecondary,
        underline: const SizedBox(),
        borderRadius: BorderRadius.circular(8),
        items: items
            .map((i) => material.DropdownMenuItem<T>(value: i.value, child: i.child))
            .toList(),
        onChanged: onChanged,
      );
    }
    return fluent.ComboBox<T>(
      value: value,
      isExpanded: isExpanded,
      style: style ?? TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      ),
      items: items
          .map((i) => fluent.ComboBoxItem<T>(value: i.value, child: i.child))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class AdaptiveMenuItem<T> {
  final T value;
  final Widget child;
  const AdaptiveMenuItem({required this.value, required this.child});
}

// ─── Internal macOS dialog helpers ───────────────────────────

Widget _appIcon() => Container(
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
      child: Icon(
        CupertinoIcons.waveform,
        color: const Color(0xFFFFFFFF),
        size: 32,
      ),
    );

macos.PushButton _macosBtn({
  required String label,
  required VoidCallback? onPressed,
  bool secondary = false,
}) =>
    macos.PushButton(
      controlSize: macos.ControlSize.large,
      secondary: secondary,
      onPressed: onPressed,
      child: Text(label),
    );

// ─── Adaptive dialogs ────────────────────────────────────────

Future<void> showAdaptiveDialog({
  required BuildContext context,
  required String title,
  required Widget content,
  required VoidCallback onConfirm,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
}) {
  if (_onMacOS) {
    return macos.showMacosAlertDialog<void>(
      context: context,
      builder: (ctx) => macos.MacosAlertDialog(
        appIcon: _appIcon(),
        title: Text(title, style: AppTheme.inter(fontSize: 14, fontWeight: FontWeight.w600)),
        message: content,
        primaryButton: _macosBtn(
          label: confirmLabel,
          onPressed: () { onConfirm(); Navigator.pop(ctx); },
        ),
        secondaryButton: _macosBtn(
          label: cancelLabel,
          onPressed: () => Navigator.pop(ctx),
          secondary: true,
        ),
      ),
    );
  }
  if (_onLinux) {
    return material.showDialog<void>(
      context: context,
      builder: (ctx) => material.AlertDialog(
        title: Text(title, style: AppTheme.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        content: content,
        backgroundColor: AppColors.bgSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          material.TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(cancelLabel, style: AppTheme.inter(fontSize: 13, color: AppColors.textTertiary)),
          ),
          material.ElevatedButton(
            onPressed: () { onConfirm(); Navigator.pop(ctx); },
            style: material.ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: material.Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(confirmLabel, style: AppTheme.inter(fontSize: 13, fontWeight: FontWeight.w500, color: material.Colors.white)),
          ),
        ],
      ),
    );
  }
  return fluent.showDialog<void>(
    context: context,
    builder: (ctx) => fluent.ContentDialog(
      title: Text(title, style: AppTheme.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      content: content,
      actions: [
        fluent.Button(
          onPressed: () => Navigator.pop(ctx),
          child: Text(cancelLabel, style: AppTheme.inter(fontSize: 12, color: AppColors.textTertiary)),
        ),
        fluent.FilledButton(
          onPressed: () { onConfirm(); Navigator.pop(ctx); },
          child: Text(confirmLabel, style: AppTheme.inter(fontSize: 12, fontWeight: FontWeight.w500)),
        ),
      ],
    ),
  );
}

Future<void> showAdaptiveStatefulDialog({
  required BuildContext context,
  required String title,
  required Widget Function(StateSetter setState) contentBuilder,
  required VoidCallback Function(BuildContext ctx, StateSetter setState) onConfirm,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
}) {
  if (_onMacOS) {
    return macos.showMacosAlertDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => macos.MacosAlertDialog(
          appIcon: _appIcon(),
          title: Text(title, style: AppTheme.inter(fontSize: 14, fontWeight: FontWeight.w600)),
          message: contentBuilder(setDialogState),
          primaryButton: _macosBtn(
            label: confirmLabel,
            onPressed: () { onConfirm(ctx, setDialogState)(); Navigator.pop(ctx); },
          ),
          secondaryButton: _macosBtn(
            label: cancelLabel,
            onPressed: () => Navigator.pop(ctx),
            secondary: true,
          ),
        ),
      ),
    );
  }
  if (_onLinux) {
    return material.showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => material.AlertDialog(
          title: Text(title, style: AppTheme.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          content: contentBuilder(setDialogState),
          backgroundColor: AppColors.bgSecondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          actions: [
            material.TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(cancelLabel, style: AppTheme.inter(fontSize: 13, color: AppColors.textTertiary)),
            ),
            material.ElevatedButton(
              onPressed: () { onConfirm(ctx, setDialogState)(); Navigator.pop(ctx); },
              style: material.ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: material.Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(confirmLabel, style: AppTheme.inter(fontSize: 13, fontWeight: FontWeight.w500, color: material.Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
  return fluent.showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => fluent.ContentDialog(
        title: Text(title, style: AppTheme.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        content: contentBuilder(setDialogState),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(ctx),
            child: Text(cancelLabel, style: AppTheme.inter(fontSize: 12, color: AppColors.textTertiary)),
          ),
          fluent.FilledButton(
            onPressed: () { onConfirm(ctx, setDialogState)(); Navigator.pop(ctx); },
            child: Text(confirmLabel, style: AppTheme.inter(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    ),
  );
}

// ─── Adaptive notification ───────────────────────────────────

void showAdaptiveNotification(
  BuildContext context, {
  required String message,
  bool isError = false,
  bool isWarning = false,
}) {
  if (_onMacOS) {
    macos.showMacosAlertDialog<void>(
      context: context,
      builder: (ctx) => macos.MacosAlertDialog(
        appIcon: _appIcon(),
        title: Text(
          isError ? 'Error' : isWarning ? 'Warning' : 'Done',
          style: AppTheme.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        message: Text(message, style: AppTheme.inter(fontSize: 12, color: AppColors.textSecondary)),
        primaryButton: _macosBtn(label: 'OK', onPressed: () => Navigator.pop(ctx)),
      ),
    );
    return;
  }
  if (_onLinux) {
    final snackBar = material.SnackBar(
      content: Text(message, style: AppTheme.inter(fontSize: 13, color: material.Colors.white)),
      backgroundColor: isError
          ? const Color(0xFFC01C28) // Adwaita red
          : isWarning
              ? const Color(0xFFE5A50A) // Adwaita yellow
              : const Color(0xFF26A269), // Adwaita green
      behavior: material.SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      duration: const Duration(seconds: 3),
    );
    material.ScaffoldMessenger.of(context).showSnackBar(snackBar);
    return;
  }
  fluent.displayInfoBar(
    context,
    builder: (ctx, close) => fluent.InfoBar(
      title: Text(message, style: AppTheme.inter(fontSize: 12)),
      severity: isError
          ? fluent.InfoBarSeverity.error
          : isWarning
              ? fluent.InfoBarSeverity.warning
              : fluent.InfoBarSeverity.success,
      onClose: close,
    ),
    duration: const Duration(seconds: 3),
  );
}
