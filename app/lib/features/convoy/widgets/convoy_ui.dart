import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';
import '../../../data/repos/convoy_models.dart';

/// Shared convoy building blocks on top of `lib/app/ui` (docs/12 §7 Convoy):
/// the status capsule, the thing that floats over the map, a borderless row
/// and a tonal action that can sit beside another one.

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
            : Text(
                caption!,
                style: context.caption,
                maxLines: 1,
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
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 22),
              const SizedBox(width: Space.sm),
            ],
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small headline with a kicker above it and one line under it, for
/// screen states that are not quite empty (radio off, mic denied).
class ConvoyNotice extends StatelessWidget {
  const ConvoyNotice({
    super.key,
    required this.headline,
    this.kicker,
    this.body,
    this.action,
    this.secondary,
  });

  final String headline;
  final String? kicker;
  final String? body;
  final Widget? action;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.xxxl,
        Space.gutter,
        Space.xxl,
      ),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 32,
        height: 4,
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
