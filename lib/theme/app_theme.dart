import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    hide
        Typography,
        Colors,
        OutlinedButton,
        SliderThemeData,
        TooltipThemeData,
        BorderSide,
        RoundedRectangleBorder;
import 'package:flutter/material.dart' as material
    show Colors, OutlinedButton, SliderThemeData, TooltipThemeData;
import 'package:fluent_ui/fluent_ui.dart'
    hide
        Colors,
        OutlinedButton,
        SliderThemeData,
        TooltipThemeData,
        Color,
        FontWeight,
        Brightness,
        TextStyle,
        BoxShadow,
        Offset;
import 'package:google_fonts/google_fonts.dart';
import 'package:macos_ui/macos_ui.dart' as macos;
import '../platform.dart' as plat;

/// Global flag toggled by ThemeService.
bool isDarkTheme = true;

// ─── Platform helpers (respect uiStyleOverride) ──────────────

bool get _isWindows => plat.isWindows;
bool get _isMacOS => plat.isMacOS;
bool get _isLinux => plat.isLinux;

class AppColors {
  AppColors._();

  static Color? customAccentOverride;

  /// Cache for dynamically extracted colors from app icons (Pid -> Color)
  static final Map<String, Color> _dynamicIconColors = {};

  static void setDynamicColor(String pid, Color color) {
    _dynamicIconColors[pid] = color;
  }

  // ─── Backgrounds ────────────────────────────────────────
  // Windows 11 Mica / macOS window / generic dark
  static Color get bgPrimary {
    if (isDarkTheme) {
      if (_isWindows) {
        return const Color(0xFF202020);
      } // Win11 Mica dark
      if (_isMacOS) {
        return const Color(0xFF1E1E1E);
      } // macOS NSWindowBg dark
      if (_isLinux) {
        return const Color(0xFF242424);
      } // Adwaita dark
      return const Color(0xFF0E0E10);
    } else {
      if (_isWindows) {
        return const Color(0xFFF3F3F3);
      } // Win11 Mica light
      if (_isMacOS) {
        return const Color(0xFFECECEC);
      } // macOS NSWindowBg light
      if (_isLinux) {
        return const Color(0xFFFAFAFA);
      } // Adwaita light
      return const Color(0xFFF5F6F8);
    }
  }

  static Color get bgSecondary {
    if (isDarkTheme) {
      if (_isWindows) {
        return const Color(0xFF2B2B2B);
      } // Win11 card surface dark
      if (_isMacOS) {
        return const Color(0xFF282828);
      } // macOS card dark
      if (_isLinux) {
        return const Color(0xFF303030);
      } // Adwaita dark card
      return const Color(0xFF18181B);
    } else {
      if (_isWindows) {
        return const Color(0xFFFFFFFF);
      }
      if (_isMacOS) {
        return const Color(0xFFFFFFFF);
      }
      if (_isLinux) {
        return const Color(0xFFFFFFFF);
      } // Adwaita light card
      return const Color(0xFFFFFFFF);
    }
  }

  static Color get bgTertiary {
    if (isDarkTheme) {
      if (_isWindows) {
        return const Color(0xFF333333);
      }
      if (_isMacOS) {
        return const Color(0xFF303030);
      }
      if (_isLinux) {
        return const Color(0xFF383838);
      } // Adwaita dark tertiary
      return const Color(0xFF1F1F23);
    } else {
      if (_isWindows) {
        return const Color(0xFFF0F0F0);
      }
      if (_isMacOS) {
        return const Color(0xFFF5F5F5);
      }
      if (_isLinux) {
        return const Color(0xFFF0F0F0);
      } // Adwaita light tertiary
      return const Color(0xFFECEDF0);
    }
  }

  static Color get bgHover {
    if (isDarkTheme) {
      if (_isWindows) {
        return const Color(0xFF3D3D3D);
      }
      if (_isMacOS) {
        return const Color(0xFF383838);
      }
      if (_isLinux) {
        return const Color(0xFF404040);
      } // Adwaita dark hover
      return const Color(0xFF26262B);
    } else {
      if (_isWindows) {
        return const Color(0xFFE8E8E8);
      }
      if (_isMacOS) {
        return const Color(0xFFE3E3E3);
      }
      if (_isLinux) {
        return const Color(0xFFE8E8E8);
      } // Adwaita light hover
      return const Color(0xFFE2E4E8);
    }
  }

  // ─── Text ────────────────────────────────────────────────
  static Color get textPrimary {
    if (isDarkTheme) {
      if (_isWindows) {
        return const Color(0xFFFFFFFF);
      }
      if (_isMacOS) {
        return const Color(0xFFEBEBEB);
      }
      if (_isLinux) {
        return const Color(0xFFFFFFFF);
      } // Adwaita dark text
      return const Color(0xFFF4F4F5);
    } else {
      if (_isWindows) {
        return const Color(0xFF000000);
      }
      if (_isMacOS) {
        return const Color(0xFF1A1A1A);
      }
      if (_isLinux) {
        return const Color(0xFF1E1E1E);
      } // Adwaita light text
      return const Color(0xFF111318);
    }
  }

  static Color get textSecondary {
    if (isDarkTheme) {
      if (_isWindows) {
        return const Color(0xFFB3B3B3);
      }
      if (_isMacOS) {
        return const Color(0xFF9E9E9E);
      }
      if (_isLinux) {
        return const Color(0xFFA0A0A0);
      } // Adwaita dark secondary
      return const Color(0xFFA1A1AA);
    } else {
      if (_isWindows) {
        return const Color(0xFF4D4D4D);
      }
      if (_isMacOS) {
        return const Color(0xFF545454);
      }
      if (_isLinux) {
        return const Color(0xFF5E5E5E);
      } // Adwaita light secondary
      return const Color(0xFF454952);
    }
  }

  static Color get textTertiary {
    if (isDarkTheme) {
      if (_isWindows) {
        return const Color(0xFF808080);
      }
      if (_isMacOS) {
        return const Color(0xFF737373);
      }
      if (_isLinux) {
        return const Color(0xFF787878);
      } // Adwaita dark tertiary
      return const Color(0xFF71717A);
    } else {
      if (_isWindows) {
        return const Color(0xFF737373);
      }
      if (_isMacOS) {
        return const Color(0xFF888888);
      }
      if (_isLinux) {
        return const Color(0xFF7E7E7E);
      } // Adwaita light tertiary
      return const Color(0xFF7C8190);
    }
  }

  // ─── Borders ─────────────────────────────────────────────
  static Color get border {
    if (isDarkTheme) {
      if (_isWindows) {
        return const Color(0x15FFFFFF);
      }
      if (_isMacOS) {
        return const Color(0x1AFFFFFF);
      }
      if (_isLinux) {
        return const Color(0x26FFFFFF);
      } // Adwaita dark border
      return const Color(0xFF27272A);
    } else {
      if (_isWindows) {
        return const Color(0x15000000);
      }
      if (_isMacOS) {
        return const Color(0x1A000000);
      }
      if (_isLinux) {
        return const Color(0x1A000000);
      } // Adwaita light border
      return const Color(0xFFD5D8DE);
    }
  }

  static Color get borderHover {
    if (isDarkTheme) {
      if (_isWindows) {
        return const Color(0x29FFFFFF);
      }
      if (_isMacOS) {
        return const Color(0x33FFFFFF);
      }
      if (_isLinux) {
        return const Color(0x40FFFFFF);
      } // Adwaita dark border hover
      return const Color(0xFF3F3F46);
    } else {
      if (_isWindows) {
        return const Color(0x29000000);
      }
      if (_isMacOS) {
        return const Color(0x33000000);
      }
      if (_isLinux) {
        return const Color(0x33000000);
      } // Adwaita light border hover
      return const Color(0xFFBCC0C8);
    }
  }

  // ─── Accent ──────────────────────────────────────────────
  static Color get accent {
    if (customAccentOverride != null) {
      return customAccentOverride!;
    }

    if (_isWindows) {
      return isDarkTheme
          ? const Color(0xFF60CDFF) // Win11 dark accent
          : const Color(0xFF0067C0); // Win11 light accent
    }
    if (_isMacOS) {
      return isDarkTheme
          ? const Color(0xFF0A84FF) // macOS dark accent
          : const Color(0xFF007AFF); // macOS light accent
    }
    if (_isLinux) {
      return isDarkTheme
          ? const Color(0xFF3584E4) // GNOME/Adwaita blue
          : const Color(0xFF1C71D8); // Adwaita light accent
    }
    return isDarkTheme ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
  }

  static Color get accentMuted {
    if (customAccentOverride != null) {
      return isDarkTheme
          ? customAccentOverride!.withValues(alpha: 0.6)
          : customAccentOverride!.withValues(alpha: 0.8);
    }

    if (_isWindows) {
      return isDarkTheme ? const Color(0xFF003E6B) : const Color(0xFFCCE4F7);
    }
    if (_isMacOS) {
      return isDarkTheme ? const Color(0xFF003A8C) : const Color(0xFFCCE4FF);
    }
    if (_isLinux) {
      return isDarkTheme
          ? const Color(0xFF1A5FB4) // Adwaita dark accent muted
          : const Color(0xFFD0E4F7); // Adwaita light accent muted
    }
    return isDarkTheme ? const Color(0xFF1D4ED8) : const Color(0xFF3B82F6);
  }

  // ─── Corner radius ───────────────────────────────────────
  /// Card/panel corner radius — matches platform conventions
  static double get cardRadius {
    if (_isWindows) {
      return 6.0;
    } // WinUI3: typically 4-8px
    if (_isMacOS) {
      return 10.0;
    } // macOS: 10-12px
    if (_isLinux) {
      return 12.0;
    } // Adwaita: 12px
    return 10.0;
  }

  /// Dialog corner radius
  static double get dialogRadius {
    if (_isWindows) {
      return 8.0;
    }
    if (_isMacOS) {
      return 12.0;
    }
    if (_isLinux) {
      return 12.0;
    } // Adwaita: 12px
    return 12.0;
  }

  // ─── App brand colors ────────────────────────────────────
  static const Color spotify = Color(0xFF1DB954);
  static const Color discord = Color(0xFF5865F2);
  static const Color chrome = Color(0xFFFF4444);
  static const Color teams = Color(0xFF6264A7);
  static const Color vlc = Color(0xFFFF8800);
  static const Color defaultApp = Color(0xFF6366F1);

  static Color get active =>
      isDarkTheme ? const Color(0xFF22C55E) : const Color(0xFF16A34A);
  static Color get inactive =>
      isDarkTheme ? const Color(0xFF52525B) : const Color(0xFFB0B5BF);

  // ─── Shadows ─────────────────────────────────────────────
  static List<BoxShadow> get cardShadow {
    if (isDarkTheme) {
      return [];
    }
    if (_isWindows) {
      return [
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: 0.08),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];
    }
    if (_isLinux) {
      return [
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: 0.06),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
    }
    return [
      BoxShadow(
        color: const Color(0xFF000000).withValues(alpha: 0.06),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ];
  }

  static List<BoxShadow> get dropdownShadow => [
        BoxShadow(
          color: isDarkTheme
              ? const Color(0xFF000000).withValues(alpha: 0.45)
              : const Color(0xFF000000).withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get dialogShadow => [
        BoxShadow(
          color: isDarkTheme
              ? const Color(0xFF000000).withValues(alpha: 0.5)
              : const Color(0xFF000000).withValues(alpha: 0.16),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  static Color getAppColor(String processName, {String? pid}) {
    // Check dynamic cache first if pid is provided
    if (pid != null && _dynamicIconColors.containsKey(pid)) {
      return _dynamicIconColors[pid]!;
    }

    final n = processName.toLowerCase();
    if (n.contains('spotify')) {
      return spotify;
    }
    if (n.contains('discord')) {
      return discord;
    }
    if (n.contains('chrome') ||
        n.contains('firefox') ||
        n.contains('brave') ||
        n.contains('edge')) {
      return chrome;
    }
    if (n.contains('teams')) {
      return teams;
    }
    if (n.contains('vlc')) {
      return vlc;
    }
    return defaultApp;
  }
}

// ─── AppTheme ────────────────────────────────────────────────

class AppTheme {
  /// Platform-aware text style.
  /// Windows → Segoe UI Variable (system font, crisp on Win11)
  /// macOS   → platform default (SF Pro via MacosApp context)
  /// Linux   → Cantarell (GNOME system font)
  /// other   → Inter (Google Fonts)
  static TextStyle inter({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    final c = color ?? AppColors.textPrimary;
    if (!kIsWeb && Platform.isWindows) {
      return TextStyle(
        fontFamily: 'Segoe UI Variable',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: c,
        letterSpacing: letterSpacing,
        height: height,
      );
    }
    if (!kIsWeb && Platform.isMacOS) {
      // null fontFamily → SF Pro via MacosApp/CupertinoApp context
      return TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: c,
        letterSpacing: letterSpacing,
        height: height,
      );
    }
    if (!kIsWeb && Platform.isLinux) {
      // Cantarell is the GNOME system font; Ubuntu uses 'Ubuntu'
      return TextStyle(
        fontFamily: 'Cantarell',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: c,
        letterSpacing: letterSpacing,
        height: height,
      );
    }
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: c,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static Typography get _typography => Typography.raw(
        caption: inter(fontSize: 11, color: AppColors.textSecondary),
        body: inter(fontSize: 13, color: AppColors.textPrimary),
        bodyStrong: inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary),
        bodyLarge: inter(fontSize: 14, color: AppColors.textPrimary),
        subtitle: inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary),
        title: inter(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary),
        titleLarge: inter(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary),
        display: inter(
            fontSize: 40,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary),
      );

  static FluentThemeData get current => FluentThemeData(
        brightness: isDarkTheme ? Brightness.dark : Brightness.light,
        accentColor: AppColors.accent.toAccentColor(),
        scaffoldBackgroundColor: AppColors.bgPrimary,
        typography: _typography,
        dialogTheme: ContentDialogThemeData(
          decoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.circular(AppColors.dialogRadius),
            border: isDarkTheme
                ? Border.all(color: AppColors.border, width: 1)
                : null,
            boxShadow: AppColors.dialogShadow,
          ),
          titleStyle: inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
          bodyStyle: inter(fontSize: 12, color: AppColors.textSecondary),
          padding: const EdgeInsets.all(20),
          actionsDecoration: BoxDecoration(
            color: AppColors.bgSecondary,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(AppColors.dialogRadius),
              bottomRight: Radius.circular(AppColors.dialogRadius),
            ),
          ),
        ),
      );

  static macos.MacosThemeData get macosCurrent => macos.MacosThemeData(
        brightness: isDarkTheme ? Brightness.dark : Brightness.light,
        primaryColor: AppColors.accent,
      );

  /// Linux/GNOME Material theme — styled to match Adwaita/libadwaita.
  static ThemeData get linuxDarkTheme => ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Cantarell',
        colorSchemeSeed: const Color(0xFF3584E4),
        scaffoldBackgroundColor: AppColors.bgPrimary,
        cardColor: AppColors.bgSecondary,
        dividerColor: AppColors.border,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.bgPrimary,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          titleTextStyle: inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        cardTheme: CardThemeData(
          color: AppColors.bgSecondary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
            side: BorderSide(color: AppColors.border, width: 1),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3584E4),
            foregroundColor: material.Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: material.OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? material.Colors.white
                  : AppColors.textTertiary),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? const Color(0xFF3584E4)
                  : AppColors.bgTertiary),
        ),
        sliderTheme: material.SliderThemeData(
          activeTrackColor: const Color(0xFF3584E4),
          inactiveTrackColor: AppColors.bgTertiary,
          thumbColor: material.Colors.white,
          overlayColor: const Color(0xFF3584E4).withValues(alpha: 0.12),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.dialogRadius),
          ),
        ),
        tooltipTheme: material.TooltipThemeData(
          decoration: BoxDecoration(
            color: AppColors.bgTertiary,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          textStyle: inter(fontSize: 12, color: AppColors.textPrimary),
        ),
      );

  static ThemeData get linuxLightTheme => ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
        fontFamily: 'Cantarell',
        colorSchemeSeed: const Color(0xFF1C71D8),
        scaffoldBackgroundColor: AppColors.bgPrimary,
        cardColor: AppColors.bgSecondary,
        dividerColor: AppColors.border,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.bgPrimary,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          titleTextStyle: inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        cardTheme: CardThemeData(
          color: AppColors.bgSecondary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
            side: BorderSide(color: AppColors.border, width: 1),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1C71D8),
            foregroundColor: material.Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: material.OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? material.Colors.white
                  : AppColors.textTertiary),
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? const Color(0xFF1C71D8)
                  : AppColors.bgTertiary),
        ),
        sliderTheme: material.SliderThemeData(
          activeTrackColor: const Color(0xFF1C71D8),
          inactiveTrackColor: AppColors.bgTertiary,
          thumbColor: const Color(0xFF1C71D8),
          overlayColor: const Color(0xFF1C71D8).withValues(alpha: 0.12),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.dialogRadius),
          ),
        ),
        tooltipTheme: material.TooltipThemeData(
          decoration: BoxDecoration(
            color: AppColors.bgTertiary,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          textStyle: inter(fontSize: 12, color: AppColors.textPrimary),
        ),
      );
}
