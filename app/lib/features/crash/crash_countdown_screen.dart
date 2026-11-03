import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/crash/crash_monitor.dart';
import '../../widgets/friendly_error.dart';

/// Full-screen "Possible crash detected" prompt (docs/01 §4.5): a 30 s
/// countdown with one huge "I'm OK" button. Also the place to resolve an
/// alert that already went out, and an honest empty state otherwise.
class CrashCountdownScreen extends ConsumerWidget {
  const CrashCountdownScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(crashMonitorProvider);
    final monitor = ref.read(crashMonitorProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

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
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.emergency_share, size: 64, color: scheme.error),
              const SizedBox(height: 16),
              Text(
                'At $when your phone reported a possible crash.',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _sentSummary(unresolved.contactsTexted, unresolved.cloudSent),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
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
              const SizedBox(height: 8),
              const Text(
                'Tells your friends you are fine and lets the trip score.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Crash detection')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_outlined, size: 56, color: scheme.primary),
              const SizedBox(height: 12),
              const Text('No crash detected.'),
              if (state.lastOutcome != null) ...[
                const SizedBox(height: 8),
                Text(
                  _outcomeText(state),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
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

class _Countdown extends StatelessWidget {
  const _Countdown({required this.state, required this.monitor});

  final CrashUiState state;
  final CrashMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return PopScope(
      // A reflex back-swipe must not dismiss the only "I'm OK" control.
      canPop: false,
      child: Scaffold(
        backgroundColor: scheme.errorContainer,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (state.testMode)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text('TEST: nothing will be sent'),
                  ),
                const SizedBox(height: 16),
                Icon(Icons.car_crash, size: 72, color: scheme.onErrorContainer),
                const SizedBox(height: 12),
                Text(
                  'Possible crash detected',
                  style: text.headlineMedium?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "Tap I'm OK if you are fine. Otherwise your contacts and "
                  'friends are alerted when the timer ends.',
                  style: text.bodyLarge?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                Text(
                  '${state.secondsLeft}',
                  key: const Key('crash-seconds'),
                  style: text.displayLarge?.copyWith(
                    fontSize: 120,
                    fontWeight: FontWeight.w900,
                    color: scheme.onErrorContainer,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 96,
                  child: FilledButton(
                    key: const Key('crash-im-ok'),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      textStyle: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
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
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    key: const Key('crash-send-help'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onErrorContainer,
                      side: BorderSide(color: scheme.onErrorContainer),
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
