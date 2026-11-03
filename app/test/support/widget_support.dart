import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps frames for [duration] of fake time in 100 ms steps. Used instead of
/// `pumpAndSettle` where drift stream updates and Riverpod rebuilds arrive
/// over several zero-duration timers.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  const step = Duration(milliseconds: 100);
  var elapsed = Duration.zero;
  while (elapsed < duration) {
    await tester.pump(step);
    elapsed += step;
  }
}

/// Unmounts the tree and lets provider disposal finish.
///
/// drift schedules a zero-duration timer when a query stream is cancelled;
/// flutter_test fails a test that ends with such a timer pending, so every
/// widget test that builds providers ends with this.
Future<void> unmountAndSettle(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pump(const Duration(milliseconds: 10));
}
