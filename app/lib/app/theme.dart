import 'package:flutter/material.dart';

/// Brand colours and the score colour scale.
///
/// Dark is the primary look: the app is used in cars at night. Light exists
/// so the OS setting is respected.
abstract final class DrivalryTheme {
  static const seed = Color(0xFFFF6A1A); // signal orange
  static const teal = Color(0xFF13C2A3);

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      navigationBarTheme: const NavigationBarThemeData(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  /// Colour for a 0-100 Drive Score. Five bands, same breakpoints as the
  /// league tiers in docs/02-game-design.md.
  static Color scoreColor(int score) {
    if (score >= 90) return const Color(0xFF2ECC71);
    if (score >= 75) return const Color(0xFF9ACD32);
    if (score >= 60) return const Color(0xFFF1C40F);
    if (score >= 40) return const Color(0xFFE67E22);
    return const Color(0xFFE74C3C);
  }
}
