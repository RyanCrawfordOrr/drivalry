import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../features/drive/widgets/score_ring.dart';
import '../theme.dart';
import 'components.dart';
import 'haptics.dart';
import 'tokens.dart';
import 'typography.dart';

/// Full-screen moment for a scored trip, a badge or a promotion (docs/12 §5).
/// The ring scales in, the verdict fades up, XP counts up, badges slide in.
/// Confetti above 90; a playful stamp below 40. One button dismisses it.
///
/// Never shown over a driving screen: callers queue it until parked.
Future<void> showCelebration(
  BuildContext context, {
  required String title,
  int? score,
  String? verdict,
  int? xp,
  List<String> badges = const [],
  bool reckless = false,
  String dismissLabel = 'Nice',
  VoidCallback? onShare,
}) {
  Haptics.success();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: Motion.celebrate,
    pageBuilder: (ctx, animation, _) => _CelebrationView(
      animation: animation,
      title: title,
      score: score,
      verdict: verdict,
      xp: xp,
      badges: badges,
      reckless: reckless,
      dismissLabel: dismissLabel,
      onShare: onShare,
    ),
    transitionBuilder: (ctx, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Motion.enter),
      child: child,
    ),
  );
}

class _CelebrationView extends StatefulWidget {
  const _CelebrationView({
    required this.animation,
    required this.title,
    required this.score,
    required this.verdict,
    required this.xp,
    required this.badges,
    required this.reckless,
    required this.dismissLabel,
    required this.onShare,
  });

  final Animation<double> animation;
  final String title;
  final int? score;
  final String? verdict;
  final int? xp;
  final List<String> badges;
  final bool reckless;
  final String dismissLabel;
  final VoidCallback? onShare;

  @override
  State<_CelebrationView> createState() => _CelebrationViewState();
}

class _CelebrationViewState extends State<_CelebrationView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  bool get _confetti => (widget.score ?? 0) >= 90 || widget.badges.isNotEmpty;
  bool get _stamp => widget.reckless || (widget.score ?? 100) < 40;

  @override
  void initState() {
    super.initState();
    if (widget.badges.isNotEmpty) {
      Future<void>.delayed(
        const Duration(milliseconds: 600),
        Haptics.celebrate,
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ring = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.45, curve: Motion.enter),
    );
    final text = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.3, 0.7, curve: Motion.enter),
    );
    final extras = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.55, 1, curve: Motion.enter),
    );
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          if (_confetti)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) => CustomPaint(
                    painter: _ConfettiPainter(
                      progress: _c.value,
                      colors: [
                        scheme.primary,
                        DrivalryTheme.teal,
                        const Color(0xFFF1C40F),
                        Colors.white,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                children: [
                  const Spacer(),
                  FadeTransition(
                    opacity: text,
                    child: Kicker(widget.title, color: Colors.white70),
                  ),
                  const SizedBox(height: Space.xl),
                  if (widget.score != null)
                    ScaleTransition(
                      scale: Tween(begin: 0.6, end: 1.0).animate(ring),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          ScoreRing(
                            score: widget.score,
                            size: 200,
                            stroke: 16,
                            label: widget.xp == null ? null : '',
                          ),
                          if (_stamp)
                            FadeTransition(
                              opacity: extras,
                              child: Transform.rotate(
                                angle: -0.28,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: scheme.error,
                                      width: 3,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    widget.reckless ? 'RECKLESS' : 'ROASTED',
                                    style: context.kicker.copyWith(
                                      color: scheme.error,
                                      fontSize: 18,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (widget.xp != null) ...[
                    const SizedBox(height: Space.lg),
                    AnimatedBuilder(
                      animation: extras,
                      builder: (_, _) => Text(
                        '+${(widget.xp! * extras.value).round()} XP',
                        style: context.title.copyWith(
                          color: Colors.white,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                  if (widget.verdict != null) ...[
                    const SizedBox(height: Space.xl),
                    FadeTransition(
                      opacity: text,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0, 0.15),
                          end: Offset.zero,
                        ).animate(text),
                        child: Text(
                          widget.verdict!,
                          textAlign: TextAlign.center,
                          style: context.headline.copyWith(
                            color: Colors.white,
                            fontSize: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (widget.badges.isNotEmpty) ...[
                    const SizedBox(height: Space.xl),
                    SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.4),
                        end: Offset.zero,
                      ).animate(extras),
                      child: FadeTransition(
                        opacity: extras,
                        child: Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.sm,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final b in widget.badges)
                              Pill(
                                b,
                                tone: PillTone.live,
                                icon: Icons.military_tech_outlined,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (widget.onShare != null) ...[
                    SecondaryButton(
                      label: 'Share',
                      icon: Icons.ios_share,
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onShare!();
                      },
                    ),
                    const SizedBox(height: Space.sm),
                  ],
                  PrimaryButton(
                    label: widget.dismissLabel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.colors});
  final double progress;
  final List<Color> colors;

  static final _seeds = List.generate(90, (i) {
    final r = math.Random(i * 7919);
    return (
      x: r.nextDouble(),
      delay: r.nextDouble() * 0.4,
      speed: 0.6 + r.nextDouble() * 0.8,
      drift: (r.nextDouble() - 0.5) * 0.3,
      size: 4 + r.nextDouble() * 6,
      spin: r.nextDouble() * math.pi * 4,
      color: r.nextInt(4),
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final s in _seeds) {
      final t = ((progress - s.delay) / (1 - s.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final y = -20 + t * t * size.height * s.speed * 1.2;
      if (y > size.height) continue;
      final x = size.width * (s.x + s.drift * t);
      paint.color = colors[s.color % colors.length].withValues(
        alpha: (1 - t).clamp(0.0, 1.0),
      );
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(s.spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: s.size,
            height: s.size * 0.6,
          ),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}
