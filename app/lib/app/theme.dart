import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'ui/tokens.dart';

/// Brand colours, type families and component themes.
///
/// Dark is the primary look: the app is used in cars at night. Light exists
/// so the OS setting is respected. Layout tokens live in `ui/tokens.dart`,
/// type roles in `ui/typography.dart`; the rebrand changes this file, those
/// two and the mark painter, nothing else (docs/12-ux-direction.md §9).
abstract final class DrivalryTheme {
  static const seed = Color(0xFFFF6A1A); // signal orange
  static const teal = Color(0xFF13C2A3);

  /// Text family for everything. Null means the platform default (Roboto on
  /// Android, SF on iOS). The rebrand bundles a family and names it here.
  static const String? fontFamily = null;

  /// Family for `display` and `headline` roles when the brand uses a second
  /// face for big numbers and titles; null falls back to [fontFamily].
  static const String? displayFontFamily = null;

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final dark = brightness == Brightness.dark;
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: fontFamily,
    );
    final text = base.textTheme;
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: Space.gutter,
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        height: 72,
      ),
      // Tiles do the work of cards (docs/12 §4); Card stays borderless and
      // flush for the screens not yet migrated.
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: Radii.cardRadius),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        minVerticalPadding: Space.md,
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: Radii.tileRadius),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: dark ? 0.4 : 0.6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(Sizes.touch, Sizes.button),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          shape: RoundedRectangleBorder(borderRadius: Radii.buttonRadius),
          textStyle: text.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(Sizes.touch, Sizes.button),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          shape: RoundedRectangleBorder(borderRadius: Radii.buttonRadius),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: text.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(Sizes.touch, Sizes.touch),
          shape: RoundedRectangleBorder(borderRadius: Radii.tileRadius),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(Sizes.touch, Sizes.touch),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: Radii.cardRadius),
        extendedPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
        extendedTextStyle: text.labelLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        labelStyle: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        showCheckmark: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainerHigh,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheetRadius),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.sheetRadius),
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: Radii.tileRadius),
        insetPadding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.gutter,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: Radii.tileRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.tileRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.tileRadius,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.lg,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          side: BorderSide(color: scheme.outlineVariant),
          minimumSize: const Size(Sizes.touch, Sizes.touch),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: text.titleSmall,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearTrackColor: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
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
