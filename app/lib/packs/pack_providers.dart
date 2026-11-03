import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/env.dart';
import '../data/db/database.dart';
import '../tracking/providers.dart';
import 'pack_manager.dart';

Future<Directory> _defaultPacksDir() async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'packs'));
}

final packManagerProvider = Provider<PackManager>(
  (ref) => PackManager(
    ref.watch(databaseProvider),
    ref.watch(httpClientProvider),
    indexUrl: Env.packIndexUrl,
    packsDir: _defaultPacksDir,
  ),
);

/// Installed packs, live.
final installedPacksProvider = StreamProvider<List<Pack>>(
  (ref) => ref.watch(databaseProvider).watchInstalledPacks(),
);
