import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';

/// [HeroNumber]'s layout with a number that counts up (docs/12 §5b):
/// kicker, [AnimatedNumber] in the display style, unit beside it, caption.
/// A null [value] shows a dash.
class CountingHero extends StatelessWidget {
  const CountingHero({
    super.key,
    required this.value,
    this.kicker,
    this.unit,
    this.caption,
    this.prefix = '',
    this.decimals = 0,
    this.small = true,
    this.color,
    this.alignment = CrossAxisAlignment.start,
  });

  final num? value;
  final String? kicker;
  final String? unit;
  final String? caption;
  final String prefix;
  final int decimals;
  final bool small;
  final Color? color;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final number = (small ? context.displaySmall : context.display).copyWith(
      color: color,
    );
    final v = value;
    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kicker != null) ...[
          Kicker(kicker!),
          const SizedBox(height: Space.sm),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (v == null)
              Text('–', style: number)
            else
              AnimatedNumber(
                value: v,
                style: number,
                prefix: prefix,
                decimals: decimals,
              ),
            if (unit != null && v != null) ...[
              const SizedBox(width: Space.sm),
              Text(unit!, style: context.label.copyWith(color: color)),
            ],
          ],
        ),
        if (caption != null) ...[
          const SizedBox(height: Space.xs),
          Text(caption!, style: context.caption),
        ],
      ],
    );
  }
}

/// A [ThinBar] that grows from empty to its value on first build and then
/// follows later values. Instant under reduce motion.
class GrowBar extends StatelessWidget {
  const GrowBar({
    super.key,
    required this.fraction,
    this.color,
    this.height = 6,
    this.duration = Motion.screen,
  });

  final double fraction;
  final Color? color;
  final double height;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fraction.clamp(0, 1).toDouble()),
      duration: context.reduceMotion ? Duration.zero : duration,
      curve: Motion.enter,
      builder: (_, v, _) => ThinBar(fraction: v, color: color, height: height),
    );
  }
}
