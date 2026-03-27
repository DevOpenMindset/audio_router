import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../platform.dart';
import '../theme/app_theme.dart';
import '../services/theme_service.dart';
import '../l10n/app_localizations.dart';

/// Shown on macOS < 14.2 where per-app routing is unavailable.
/// Returns an empty box on Windows or macOS 14.2+.
class MacOsRoutingBanner extends StatefulWidget {
  const MacOsRoutingBanner({super.key});

  @override
  State<MacOsRoutingBanner> createState() => _MacOsRoutingBannerState();
}

class _MacOsRoutingBannerState extends State<MacOsRoutingBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    // Only relevant on macOS with limited routing
    if (!Platform.isMacOS || routingNativelySupported || _dismissed) {
      return const SizedBox.shrink();
    }

    context.watch<ThemeService>();
    final l10n = context.l10n;
    final version = macOsVersionString ?? 'current';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2A1F00),
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          border: Border.all(color: const Color(0xFF7A5500), width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('⚠', style: TextStyle(fontSize: 14, height: 1.4,
                color: Color(0xFFFFC107))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.routingLimitedTitle(version),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFFC107),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.routingLimitedBody,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFBB9000),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _dismissed = true),
              child: const Text('✕',
                style: TextStyle(fontSize: 12, color: Color(0xFF7A5500))),
            ),
          ],
        ),
      ),
    );
  }
}
