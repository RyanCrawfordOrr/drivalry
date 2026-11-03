import 'package:flutter/material.dart';

import '../theme.dart';

/// Type roles from docs/12-ux-direction.md §3. Screens ask for a role, never
/// a size, so the rebrand changes families and scale here only.
extension DrivalryType on BuildContext {
  TextTheme get _t => Theme.of(this).textTheme;
  ColorScheme get _c => Theme.of(this).colorScheme;

  static const _tabular = [FontFeature.tabularFigures()];

  /// The live speed, the score on the trip screen, Wrapped numbers.
  TextStyle get display => _t.displayMedium!.copyWith(
    fontFamily: DrivalryTheme.displayFontFamily ?? DrivalryTheme.fontFamily,
    fontSize: 64,
    fontWeight: FontWeight.w800,
    letterSpacing: -2,
    height: 1,
    fontFeatures: _tabular,
    color: _c.onSurface,
  );

  /// A smaller display for numbers inside tiles (rank, XP, hero stats).
  TextStyle get displaySmall =>
      display.copyWith(fontSize: 40, letterSpacing: -1.2);

  /// Screen titles on editorial screens, verdicts.
  TextStyle get headline => _t.headlineMedium!.copyWith(
    fontFamily: DrivalryTheme.displayFontFamily ?? DrivalryTheme.fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.15,
    color: _c.onSurface,
  );

  /// Card titles, names.
  TextStyle get title => _t.titleLarge!.copyWith(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: _c.onSurface,
  );

  TextStyle get body =>
      _t.bodyLarge!.copyWith(fontSize: 16, height: 1.35, color: _c.onSurface);

  TextStyle get bodyMuted => body.copyWith(color: _c.onSurfaceVariant);

  /// Buttons, chips, table figures.
  TextStyle get label => _t.labelLarge!.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontFeatures: _tabular,
    color: _c.onSurface,
  );

  /// The small uppercase label above a number or a section.
  TextStyle get kicker => _t.labelSmall!.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
    height: 1.2,
    color: _c.onSurfaceVariant,
  );

  /// Timestamps, units, helper text.
  TextStyle get caption => _t.bodySmall!.copyWith(
    fontSize: 13,
    height: 1.3,
    color: _c.onSurfaceVariant,
  );
}
