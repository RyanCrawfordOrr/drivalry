import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../data/db/database.dart';
import '../data/sync/sync_bootstrap.dart';
import '../packs/pack_providers.dart';
import '../tracking/providers.dart';
import '../tracking/tracking_controller.dart';

/// Resolves to true once the Google Maps SDK may be used on this device.
///
/// iOS needs `GMSServices.provideAPIKey` before the first map is created or
/// the process aborts, and the key travels over the tracking channel, so a
/// `GoogleMap` must only be built after this provider has a value. Android
/// reads the key from the manifest and the call is a no-op there. False when
/// the build has no key at all.
final mapsReadyProvider = FutureProvider<bool>((ref) async {
  if (!Env.hasGoogleMaps) return false;
  try {
    await ref.read(trackingPortProvider).setMapsApiKey(Env.googleMapsApiKey);
    return true;
  } catch (e) {
    debugPrint('setMapsApiKey failed: $e');
    return false;
  }
});

/// Start-up work that must not block the first frame: the Maps key, the
/// sample TTL purge, stale pack temp files, and booting the tracking
/// controller. The app renders immediately and watches this provider only to
/// keep it alive.
final appBootstrapProvider = FutureProvider<void>((ref) async {
  // Keep the controller alive for the life of the app; it boots itself.
  ref.watch(trackingControllerProvider);
  // Cloud sync: outbox handlers, uploader, push, periodic drains.
  ref.watch(syncBootstrapProvider);
  await ref.watch(mapsReadyProvider.future);
  try {
    final removed = await ref
        .read(databaseProvider)
        .purgeOldSamples(DateTime.now().millisecondsSinceEpoch);
    if (removed > 0) debugPrint('purged $removed samples older than 90 days');
  } catch (e) {
    debugPrint('sample purge failed: $e');
  }
  try {
    final swept = await ref.read(packManagerProvider).sweepTempFiles();
    if (swept > 0) debugPrint('removed $swept stale pack temp files');
  } catch (e) {
    debugPrint('pack temp sweep failed: $e');
  }
});
