import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:macos_ui/macos_ui.dart' as macos;
import 'package:provider/provider.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/audio_service.dart';
import 'services/theme_service.dart';
import 'services/custom_name_service.dart';
import 'services/update_service.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'platform.dart' as _plat;

late final SystemTray _systemTray;
AudioService? _audioService; // global ref for reset-on-quit

Future<void> _initSystemTray() async {
  _systemTray = SystemTray();

  // Get absolute path to icon - platform specific
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  String iconPath;
  String fallbackIcon;
  
  if (Platform.isMacOS) {
    iconPath = '$exeDir/../Frameworks/App.framework/Resources/flutter_assets/assets/tray_icon.png';
    fallbackIcon = '$exeDir/../Resources/app_icon.png';
  } else {
    iconPath = '$exeDir\\data\\flutter_assets\\assets\\tray_icon.ico';
    fallbackIcon = '$exeDir\\windows\\runner\\resources\\app_icon.ico';
  }

  final finalIconPath = File(iconPath).existsSync()
      ? iconPath
      : (File(fallbackIcon).existsSync() ? fallbackIcon : null);

  try {
    await _systemTray.initSystemTray(
      title: 'AudioRouter',
      iconPath: finalIconPath ?? fallbackIcon,
      toolTip: 'AudioRouter — per-app audio routing',
    );
  } catch (e) {
    debugPrint('Failed to init system tray: $e');
    return;
  }

  final menu = Menu();
  await menu.buildFrom([
    MenuItemLabel(
      label: 'Show',
      onClicked: (_) async {
        await windowManager.show();
        await windowManager.focus();
      },
    ),
    MenuSeparator(),
    MenuItemLabel(
      label: 'Quit',
      onClicked: (_) async {
        _audioService?.resetAllRoutes();
        await windowManager.setPreventClose(false);
        await windowManager.close();
      },
    ),
  ]);
  await _systemTray.setContextMenu(menu);

  _systemTray.registerSystemTrayEventHandler((eventName) {
    if (eventName == kSystemTrayEventClick ||
        eventName == kSystemTrayEventDoubleClick) {
      windowManager.show();
      windowManager.focus();
    } else if (eventName == kSystemTrayEventRightClick) {
      _systemTray.popUpContextMenu();
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();

  await windowManager.ensureInitialized();
  
  // Load saved taskbar preference (default: show in Dock on macOS, hide on Windows)
  final showInTaskbar = prefs.getBool('show_in_taskbar') ??
      (Platform.isMacOS ? true : false);

  // Restore saved window size (default 380×560, min 340×420, no max)
  final savedW = prefs.getDouble('window_width')  ?? 380.0;
  final savedH = prefs.getDouble('window_height') ?? 560.0;

  // Platform-specific window options
  final windowOptions = WindowOptions(
    size: Size(savedW, savedH),
    minimumSize: const Size(340, 420),
    center: prefs.getDouble('window_width') == null, // only center on first launch
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
    skipTaskbar: !showInTaskbar,
    alwaysOnTop: false,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setResizable(true);
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setPreventClose(true);
  });

  await _initSystemTray();

  runApp(AudioRouterApp(prefs: prefs));
}

class AudioRouterApp extends StatelessWidget {
  final SharedPreferences prefs;
  
  const AudioRouterApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => _audioService = AudioService()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider(create: (_) => CustomNameService()),
        Provider<UpdateService>(create: (_) => UpdateService(prefs)),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, _) {
          // Root widget is always determined by the *real* hardware platform.
          // uiStyleOverride only changes visual appearance (colours, radii,
          // fonts, title bar layout) — never the widget framework, so all
          // fluent_ui / macos_ui internal widgets keep their required ancestors.
          if (Platform.isMacOS) {
            return macos.MacosApp(
              title: 'AudioRouter',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.macosCurrent,
              home: macos.MacosWindow(child: const HomeScreen()),
            );
          }
          return FluentApp(
            title: 'AudioRouter',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.current,
            // When the user picks macOS style on Windows hardware, inject a
            // MacosTheme + MacosWindow ABOVE the Navigator so every macos_ui
            // widget (switches, sliders, dialogs, sheets…) finds its ancestor.
            // Inject MacosTheme above the Navigator so all macos_ui leaf
            // widgets (MacosSwitch, MacosSlider, MacosPopupButton, …) find
            // their required ancestor when the user picks the macOS style.
            // We do NOT use MacosWindow/MacosScaffold here — those rely on
            // native macOS window vibrancy and go transparent on Windows.
            builder: (ctx, child) {
              if (_plat.isMacOS) {
                return macos.MacosTheme(
                  data: AppTheme.macosCurrent,
                  child: child!,
                );
              }
              return child!;
            },
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
