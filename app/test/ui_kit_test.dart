import 'package:drivalry/app/theme.dart';
import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/widgets/friendly_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: DrivalryTheme.dark(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  setUp(() => Haptics.enabled = false);

  testWidgets('components render with the theme', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      wrap(
        Column(
          children: [
            const Kicker('last trip'),
            EditorialSection(
              kicker: 'this week',
              actionLabel: 'All',
              onAction: () {},
              child: const HeroNumber(
                kicker: 'drive score',
                value: '87',
                unit: 'avg',
                caption: 'Best 97',
              ),
            ),
            Tile(onTap: () => tapped++, child: const Text('tile')),
            const StatGrid(
              children: [
                StatTile(value: '9.2 mi', label: 'Distance'),
                StatTile(value: '23 min', label: 'Moving'),
                StatTile(value: '24 mph', label: 'Average'),
                StatTile(value: '48 mph', label: 'Top'),
              ],
            ),
            PrimaryButton(label: 'Allow', onPressed: () {}),
            const PrimaryButton(label: 'Busy', onPressed: null, busy: true),
            SecondaryButton(label: 'Later', onPressed: () {}),
            const Pill('Recording', tone: PillTone.live, dot: true),
            const Avatar(name: 'Priya Patel', isMe: true),
            const ThinBar(fraction: 0.4),
            const SkeletonTile(),
            EmptyState(
              kicker: 'friends',
              headline: 'Nothing yet.',
              body: 'Add a friend and the roasts start.',
              actionLabel: 'Add friend',
              onAction: () {},
            ),
          ],
        ),
      ),
    );
    expect(find.text('LAST TRIP'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('87'), findsOneWidget);
    expect(find.text('PP'), findsOneWidget);
    expect(find.text('Nothing yet.'), findsOneWidget);
    await tester.tap(find.text('tile'));
    await tester.pump();
    expect(tapped, 1);
    final button = tester.getSize(find.widgetWithText(FilledButton, 'Allow'));
    expect(button.height, Sizes.button);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a celebration shows the ring, verdict and badges', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final future = showCelebration(
      ctx,
      title: 'Trip scored',
      score: 94,
      verdict: 'Butter smooth.',
      xp: 70,
      badges: const ['Flawless'],
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('TRIP SCORED'), findsOneWidget);
    expect(find.text('94'), findsOneWidget);
    expect(find.text('Butter smooth.'), findsOneWidget);
    expect(find.text('+70 XP'), findsOneWidget);
    expect(find.text('Flawless'), findsOneWidget);
    await tester.tap(find.text('Nice'));
    await tester.pumpAndSettle();
    await future;
    expect(find.text('94'), findsNothing);
  });

  testWidgets('motion primitives animate and settle', (tester) async {
    var taps = 0;
    var longs = 0;
    await tester.pumpWidget(
      wrap(
        Column(
          children: [
            PressScale(
              onTap: () => taps++,
              onLongPress: () => longs++,
              child: const SizedBox(
                width: 120,
                height: 48,
                child: Text('press'),
              ),
            ),
            Reveal(delay: Reveal.stagger(3), child: const Text('revealed')),
            Builder(
              builder: (c) =>
                  AnimatedNumber(value: 87, style: c.display, suffix: ' pts'),
            ),
            const PulsingDot(color: Colors.red),
            const StateSwitcher(child: Text('a', key: ValueKey('a'))),
          ],
        ),
      ),
    );
    // Mid-way the number is still counting; afterwards it has landed.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('87 pts'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('87 pts'), findsOneWidget);
    expect(find.text('revealed'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('press')),
    );
    await tester.pump(const Duration(milliseconds: 150));
    final pressed = tester.widget<AnimatedScale>(
      find.ancestor(
        of: find.text('press'),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(pressed.scale, 0.97);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
    await tester.longPress(find.text('press'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(longs, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion disables the entrance and press animations', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DrivalryTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Column(
              children: [
                PressScale(onTap: () {}, child: const Text('press')),
                const Reveal(child: Text('now')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(Reveal),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('press')),
    );
    await tester.pump(const Duration(milliseconds: 150));
    final scale = tester.widget<AnimatedScale>(
      find.ancestor(
        of: find.text('press'),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(scale.scale, 1);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
  });

  test('friendlyError never leaks the exception text', () {
    expect(
      friendlyError(Exception('boom')),
      'Something went wrong. Try again.',
    );
    expect(
      friendlyError(
        Exception('SocketException: Failed host lookup'),
        doing: 'load',
      ),
      contains('No connection'),
    );
    expect(
      friendlyError(StateError('x'), doing: 'share'),
      'Could not share. Try again.',
    );
    expect(
      friendlyError(Exception('Offline build.')),
      'Not available in this version yet.',
    );
  });
}
