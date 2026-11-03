import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/push/push_service.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

void main() {
  final skip = skipWithoutSqlite();

  test(
    'without Firebase configuration push is unavailable and start is a no-op',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final status = container.read(pushControllerProvider);
      expect(status, isA<PushUnavailable>());
      // No platform channels are touched: this would throw otherwise.
      await container.read(pushControllerProvider.notifier).start();
      expect(container.read(pushControllerProvider), isA<PushUnavailable>());
      // The outbox handler is registered regardless, so tokens queued by an
      // older build still drain once a session exists.
      expect(
        container.read(outboxWorkerProvider).handles(PushController.kindToken),
        isTrue,
      );
      // unregister without a token is harmless.
      await container.read(pushControllerProvider.notifier).unregister();
    },
    skip: skip,
  );
}
