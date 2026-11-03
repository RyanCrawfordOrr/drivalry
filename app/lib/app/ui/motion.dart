import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'haptics.dart';
import 'tokens.dart';

/// Motion primitives for the premium feel (docs/12-ux-direction.md §5b).
/// Every one respects the system "reduce motion" setting.

extension ReduceMotion on BuildContext {
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);
}

/// Scales its child down while pressed and springs back on release.
///
/// With [onTap] or [onLongPress] it owns the gesture and adds the haptic.
/// Without them it is passive: it only watches raw pointer events, so an
/// inner `InkWell` or button keeps its own tap handling and ripple while the
/// whole surface still gets the press feel (that is how `Tile` uses it).
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = true,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final HitTestBehavior behavior;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  Offset? _start;

  bool get _owns => widget.onTap != null || widget.onLongPress != null;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    final scaled = AnimatedScale(
      scale: _down && !reduce ? widget.scale : 1,
      duration: _down ? Motion.quick : Motion.reveal,
      curve: _down ? Curves.easeOut : Curves.elasticOut,
      child: widget.child,
    );
    if (!_owns) {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          _start = e.position;
          _set(true);
        },
        onPointerMove: (e) {
          // A drag (scrolling) is not a press.
          if (_start != null && (e.position - _start!).distance > 12) {
            _set(false);
          }
        },
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: scaled,
      );
    }
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) Haptics.tap();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(false);
              if (widget.haptic) Haptics.select();
              widget.onLongPress!();
            },
      child: scaled,
    );
  }
}

/// Fades and slides its child in once, on first build. Use [Reveal.stagger]
/// for list items so they arrive one after another.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.08),
    this.duration = Motion.screen,
  });

  /// Delay for the [index]th item of a list, capped so long lists do not wait.
  static Duration stagger(int index, {int step = 40, int maxItems = 8}) =>
      Duration(milliseconds: step * math.min(index, maxItems));

  final Widget child;
  final Duration delay;
  final Offset offset;
  final Duration duration;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Motion.enter,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(
        position: Tween(begin: widget.offset, end: Offset.zero).animate(_a),
        child: widget.child,
      ),
    );
  }
}

/// A number that counts from its previous value to the new one. Tabular
/// figures keep the width steady while it moves.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    required this.style,
    this.decimals = 0,
    this.prefix = '',
    this.suffix = '',
    this.duration = const Duration(milliseconds: 700),
    this.textAlign,
  });

  final num value;
  final TextStyle style;
  final int decimals;
  final String prefix;
  final String suffix;
  final Duration duration;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    return TweenAnimationBuilder<double>(
      // begin 0 makes the first appearance count up; later changes animate
      // from the value on screen.
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: reduce ? Duration.zero : duration,
      curve: Motion.enter,
      builder: (_, v, _) => Text(
        '$prefix${v.toStringAsFixed(decimals)}$suffix',
        textAlign: textAlign,
        style: style.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A moving highlight over placeholder content while it loads.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || context.reduceMotion) return widget.child;
    final highlight = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.06);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) {
          final dx = (_c.value * 2 - 0.5) * rect.width;
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.transparent, highlight, Colors.transparent],
            stops: const [0.35, 0.5, 0.65],
            transform: _Slide(dx),
          ).createShader(rect);
        },
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _Slide extends GradientTransform {
  const _Slide(this.dx);
  final double dx;
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

/// A dot that breathes, for "recording", "talking" and "live" states.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, required this.color, this.size = 10});
  final Color color;
  final double size;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    return SizedBox.square(
      dimension: widget.size * 2,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = reduce ? 0.0 : Curves.easeInOut.transform(_c.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.size * (1 + t),
                height: widget.size * (1 + t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.35 * (1 - t)),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Cross-fades and resizes between states of a card (idle to recording,
/// loading to loaded). Children must have distinct keys.
class StateSwitcher extends StatelessWidget {
  const StateSwitcher({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: Motion.screen,
      curve: Motion.standard,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: Motion.reveal,
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: child,
      ),
    );
  }
}
