import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// One store screenshot: a real screen with seeded data, plus the marketing
/// line that goes above it.
///
/// A scene builds the full tree that goes inside the phone mock-up: a
/// `ProviderScope` with fakes around a `MaterialApp` on the dark theme. It is
/// created and disposed inside one `testWidgets` body, so it may open an
/// in-memory database and must close it in [dispose].
abstract class ArtScene {
  /// File stem, e.g. `01-drive`. Sorted order is the store order.
  String get id;

  /// Two short lines, the first is the headline.
  String get headline;
  String get subline;

  /// Fake time pumped before capture, so streams and animations settle.
  Duration get settle => const Duration(seconds: 2);

  Future<Widget> build();

  /// Runs after the first frames: scroll, tap, emit fake events.
  Future<void> prepare(WidgetTester tester) async {}

  Future<void> dispose() async {}
}
