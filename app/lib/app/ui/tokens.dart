import 'package:flutter/material.dart';

/// Layout tokens from docs/12-ux-direction.md §2. Only these values appear in
/// padding, radii and sizes; the rebrand may change them here in one place.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  /// Screen-edge padding for lists and sheets.
  static const gutter = 20.0;

  /// Gap between editorial sections.
  static const section = 32.0;

  static const screen = EdgeInsets.symmetric(horizontal: gutter);
  static const screenWithBottom = EdgeInsets.fromLTRB(gutter, 0, gutter, xxxl);
}

abstract final class Radii {
  static const tile = 16.0;
  static const card = 20.0;
  static const sheet = 28.0;
  static const button = 16.0;

  static final BorderRadius tileRadius = BorderRadius.circular(tile);
  static final BorderRadius cardRadius = BorderRadius.circular(card);
  static final BorderRadius buttonRadius = BorderRadius.circular(button);
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
}

abstract final class Sizes {
  /// Minimum touch target anywhere.
  static const touch = 48.0;

  /// Touch target on screens looked at while driving (radio, stops, live card).
  static const drivingTouch = 64.0;

  /// Primary and secondary buttons.
  static const button = 56.0;
}

/// Durations and curves (docs/12 §5). Enter with emphasized decelerate, leave
/// with emphasized accelerate.
abstract final class Motion {
  static const quick = Duration(milliseconds: 120);
  static const reveal = Duration(milliseconds: 200);
  static const screen = Duration(milliseconds: 280);
  static const celebrate = Duration(milliseconds: 400);

  static const Curve enter = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Curve exit = Cubic(0.3, 0.0, 0.8, 0.15);
  static const Curve standard = Curves.easeInOutCubicEmphasized;
}
