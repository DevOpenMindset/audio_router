import 'dart:io' show Platform;
import 'dart:ui' show Offset;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// macOS menu-bar panel behavior: the main window acts like a status-bar
/// popover — the tray icon toggles it, it opens pinned to the top-right of
/// the screen just below the menu bar, and it hides when it loses focus.
class PanelController {
  PanelController._();

  static DateTime? _lastAutoHide;

  /// Panel behavior only applies on real macOS.
  static bool get enabled => Platform.isMacOS;

  /// Called from onWindowBlur: hide and remember when, so a tray click that
  /// caused the blur doesn't immediately re-open the panel.
  static Future<void> hideFromBlur() async {
    _lastAutoHide = DateTime.now();
    await windowManager.hide();
  }

  /// Tray-icon click: toggle the panel.
  static Future<void> toggleFromTray() async {
    final last = _lastAutoHide;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(milliseconds: 300)) {
      // The click itself blurred (and hid) the open panel — treat as "close".
      return;
    }
    if (await windowManager.isVisible()) {
      await windowManager.hide();
      return;
    }
    await positionUnderMenuBar();
    await windowManager.show();
    await windowManager.focus();
  }

  /// Pin the window under the menu bar, centered on the tray icon. The tray
  /// plugin doesn't expose the icon's frame, but at the moment of the click
  /// the cursor IS on the icon, so centering on the cursor aligns the panel
  /// with it (clamped to the screen edges).
  static Future<void> positionUnderMenuBar() async {
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final cursor = await screenRetriever.getCursorScreenPoint();
      final size = await windowManager.getSize();
      // visiblePosition.dy is the menu-bar inset on macOS.
      final topInset = display.visiblePosition?.dy ?? 25;
      double x = cursor.dx - size.width / 2;
      final maxX = display.size.width - size.width - 8;
      if (x > maxX) x = maxX;
      if (x < 8) x = 8;
      await windowManager.setPosition(Offset(x, topInset + 6));
    } catch (_) {
      // Positioning is cosmetic — never block showing the window on it.
    }
  }
}
