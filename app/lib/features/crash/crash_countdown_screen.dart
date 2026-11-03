import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/ui/ui.dart';
import '../../data/crash/crash_monitor.dart';
import '../../widgets/friendly_error.dart';

/// Full-screen "Possible crash detected" prompt (docs/01 §4.5): a 30 s
/// countdown with one huge "I'm OK" button. Also the place to resolve an
/// alert that already went out, and an honest empty state otherwise. Plain
/// throughout: the crash flow is the one place with no jokes (docs/12 §6).
class CrashCountdownScreen extends ConsumerWidget {
  const CrashCountdownScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(crashMonitorProvider);
    final monitor = ref.read(crashMonitorProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final bottom = Space.xl + MediaQuery.paddingOf(context).bottom;

    if (state.countingDown) {
      return _Countdown(state: state, monitor: monitor);
    }
    final unresolved = state.unresolved;
    if (unresolved != null) {
      final when = DateFormat.jm().format(
        DateTime.fromMillisecondsSinceEpoch(unresolved.createdAt),
      );
      return Scaffold(
        appBar: AppBar(title: const Text('Help was requested')),
        body: Padding(
          padding: EdgeInsets.fromLTRB(
            Space.gutter,
            Space.lg,
            Space.gutter,
            bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.emergency_share, size: 64, color: scheme.error),
              const SizedBox(height: Space.lg),
              Text(
                'At $when your phone reported a possible crash.',
                style: context.title,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.md),
              Text(
                _sentSummary(unresolved.contactsTexted, unresolved.cloudSent),
                style: context.bodyMuted,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                height: 72,
                child: FilledButton.icon(
                  key: const Key('crash-resolve'),
                  onPressed: () async {
                    try {
                      await monitor.resolveUnresolved();
                    } catch (e) {
                      if (context.mounted) {
                        _toast(
                          context,
                          friendlyError(e, doing: 'tell your friends'),
                        );
                      }
                      return;
                    }
                    if (context.mounted) await Navigator.of(context).maybePop();
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 32),
                  label: const Text(
                    "I'm OK now",
                    style: TextStyle(fontSize: 22),
                  ),
                ),
              ),
              const SizedBox(height: Space.sm),
              Text(
                'Tells your friends you are fine and lets the trip score.',
                style: context.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Crash detection')),
      body: ListView(
        padding: EdgeInsets.only(bottom: bottom),
        children: [
          EmptyState(
            kicker: 'Crash detection',
            headline: 'No crash detected.',
            body: state.lastOutcome == null ? null : _outcomeText(state),
            actionLabel: 'Close',
            onAction: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  static String _sentSummary(int texted, bool cloudSent) {
    final parts = <String>[
      cloudSent
          ? 'Friends and circle members who use Drivalry were notified.'
          : 'The alert to friends is queued and goes out as soon as the '
                'phone is online.',
      if (texted > 0)
        'A text with your location was prepared for $texted emergency '
            '${texted == 1 ? 'contact' : 'contacts'}.',
      'No calls were made.',
    ];
    return parts.join(' ');
  }

  static String _outcomeText(CrashUiState s) => switch (s.lastOutcome) {
    null => '',
    _ when s.testMode => 'Test finished. Nothing was sent.',
    _ => 'Last check: you answered in time. Nothing was sent.',
  };
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// The countdown itself: icon, one headline, one line of what happens, the
/// seconds as a 120 px display number, then a 96 px "I'm OK" and a 56 px
/// "Send help now". Both buttons clear the home indicator.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.state, required this.monitor});

  final CrashUiState state;
  final CrashMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onErrorContainer;
    return PopScope(
      // A reflex back-swipe must not dismiss the only "I'm OK" control.
      canPop: false,
      child: Scaffold(
        backgroundColor: scheme.errorContainer,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.lg,
              Space.gutter,
              Space.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.testMode)
                  const Center(child: Pill('TEST: nothing will be sent')),
                const SizedBox(height: Space.lg),
                Icon(Icons.car_crash, size: 72, color: fg),
                const SizedBox(height: Space.md),
                Text(
                  'Possible crash detected',
                  style: context.headline.copyWith(color: fg),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.sm),
                Text(
                  "Tap I'm OK if you are fine. Otherwise your contacts and "
                  'friends are alerted when the timer ends.',
                  style: context.body.copyWith(color: fg),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                Kicker('Seconds left', color: fg, textAlign: TextAlign.center),
                const SizedBox(height: Space.xs),
                Text(
                  '${state.secondsLeft}',
                  key: const Key('crash-seconds'),
                  textAlign: TextAlign.center,
                  style: context.display.copyWith(
                    fontSize: 120,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -4,
                    color: fg,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 96,
                  child: FilledButton(
                    key: const Key('crash-im-ok'),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      // A button's textStyle replaces the theme's, so it
                      // must carry the app face, not only the size.
                      textStyle: context.title.copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () async {
                      try {
                        await monitor.imOk();
                      } catch (e) {
                        if (context.mounted) {
                          _toast(
                            context,
                            friendlyError(e, doing: 'stop the countdown'),
                          );
                        }
                        return;
                      }
                      // Plain pop: PopScope only blocks system back/maybePop.
                      if (context.mounted && Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: const Text("I'm OK"),
                  ),
                ),
                const SizedBox(height: Space.md),
                SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    key: const Key('crash-send-help'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: fg,
                      side: BorderSide(color: fg),
                    ),
                    onPressed: () async {
                      try {
                        await monitor.sendHelpNow();
                      } catch (e) {
                        if (context.mounted) {
                          _toast(context, friendlyError(e, doing: 'send help'));
                        }
                      }
                    },
                    icon: const Icon(Icons.emergency_share),
                    label: const Text('Send help now'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
