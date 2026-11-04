import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';
import '../../../data/repos/convoy_models.dart';

/// Shared convoy building blocks on top of `lib/app/ui` (docs/12 §7 Convoy):
/// the status capsule, the thing that floats over the map, a borderless row
/// and a tonal action that can sit beside another one.

/// Bottom padding for a scrolling page: the last row clears the gesture bar
/// or the home indicator by at least 24 (docs/12 §2). Inside the tab shell
/// the navigation bar already takes the inset, so this is 24 there.
double pageBottomInset(BuildContext context) =>
    Space.xl + MediaQuery.paddingOf(context).bottom;

/// [showDrivalrySheet] with the sheet's last control kept clear of the
/// gesture bar and the home indicator. The kit sheet leaves the bottom inset
/// to its content; every convoy sheet opens through this until it pads it
/// itself, at which point this becomes a plain alias.
Future<T?> showConvoySheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool scrollable = false,
}) => showDrivalrySheet<T>(
  context,
  title: title,
  scrollable: scrollable,
  // The kit sheet clears the gesture bar and home indicator itself.
  builder: builder,
);

/// Status capsule for a convoy's lifecycle (docs/10 §2).
Pill convoyStatusPill(ConvoyStatus status, {bool compact = false}) =>
    switch (status) {
      ConvoyStatus.active => Pill(
        'On the road',
        tone: PillTone.live,
        dot: true,
        compact: compact,
      ),
      ConvoyStatus.planning => Pill(
        'Planning',
        tone: PillTone.primary,
        compact: compact,
      ),
      ConvoyStatus.ended => Pill('Ended', compact: compact),
    };

/// A capsule that floats over the map: tonal, pill-shaped, soft shadow
/// (docs/12 §2, "things floating over the map").
class FloatingCapsule extends StatelessWidget {
  const FloatingCapsule({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A borderless list row: leading, title, caption or a custom subtitle,
/// trailing. At least 48 tall; a tap gives a ripple and a light haptic.
class ConvoyRow extends StatelessWidget {
  const ConvoyRow({
    super.key,
    required this.title,
    this.leading,
    this.caption,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleStyle,
    this.padding = const EdgeInsets.symmetric(vertical: Space.md),
  });

  final String title;
  final Widget? leading;
  final String? caption;

  /// Replaces [caption] when a styled line is needed.
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final TextStyle? titleStyle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final sub =
        subtitle ??
        (caption == null
            ? null
            // Two lines on a narrow phone rather than an ellipsis.
            : Text(
                caption!,
                style: context.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ));
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Sizes.touch),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: Space.md)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: titleStyle ?? context.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sub != null) ...[const SizedBox(height: Space.xs), sub],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: Space.md),
              trailing!,
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: Radii.tileRadius,
        onTap: () {
          Haptics.tap();
          onTap!();
        },
        child: row,
      ),
    );
  }
}

/// A tonal action sized to share a row with another one: same height as
/// [SecondaryButton], tighter padding so two labels fit on a narrow phone.
/// A label that still does not fit at 360 wide wraps to a second line; a
/// label is never cut to an ellipsis (docs/12 §2).
class PairedAction extends StatelessWidget {
  const PairedAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = Sizes.button,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 22),
              const SizedBox(width: Space.sm),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small headline with a kicker above it and one line under it, for
/// screen states that are not quite empty (radio off, mic denied) and for
/// an empty section that follows other content.
///
/// At the top of a page it starts 24 under the app bar (docs/12 §2: content
/// starts 16 to 24 below it); pass [padding] to tighten it under a section.
class ConvoyNotice extends StatelessWidget {
  const ConvoyNotice({
    super.key,
    required this.headline,
    this.kicker,
    this.body,
    this.action,
    this.secondary,
    this.padding = const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.xl,
      Space.gutter,
      Space.xxl,
    ),
  });

  final String headline;
  final String? kicker;
  final String? body;
  final Widget? action;
  final Widget? secondary;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kicker != null) ...[
            Kicker(kicker!),
            const SizedBox(height: Space.md),
          ],
          Text(headline, style: context.headline),
          if (body != null) ...[
            const SizedBox(height: Space.md),
            Text(body!, style: context.bodyMuted),
          ],
          if (action != null) ...[const SizedBox(height: Space.xl), action!],
          if (secondary != null) ...[
            const SizedBox(height: Space.sm),
            secondary!,
          ],
        ],
      ),
    );
  }
}

/// The status pill, with a breathing dot while the convoy is on the road
/// (docs/12 §5b, "live things breathe").
class ConvoyStatusBadge extends StatelessWidget {
  const ConvoyStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  final ConvoyStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (status != ConvoyStatus.active) {
      return convoyStatusPill(status, compact: compact);
    }
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PulsingDot(color: scheme.primary, size: 8),
        const SizedBox(width: Space.xs),
        Pill('On the road', tone: PillTone.live, compact: compact),
      ],
    );
  }
}

/// A neutral pill whose number counts to its value (an ETA, a gap).
class NumberPill extends StatelessWidget {
  const NumberPill({
    super.key,
    required this.value,
    this.prefix = '',
    this.suffix = '',
    this.decimals = 0,
    this.compact = false,
  });

  final num value;
  final String prefix;
  final String suffix;
  final int decimals;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Space.sm : Space.md,
        vertical: compact ? 2 : 6,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedNumber(
        value: value,
        prefix: prefix,
        suffix: suffix,
        decimals: decimals,
        style: context.label,
      ),
    );
  }
}

/// The drag handle at the top of a sheet.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  static const double height = 4;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 32,
        height: height,
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
