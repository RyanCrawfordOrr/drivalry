import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bootstrap.dart';
import 'router.dart';
import 'theme.dart';

/// Root widget. Owns the router and the theme; everything else lives in
/// `features/`.
class DrivalryApp extends ConsumerWidget {
  const DrivalryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appBootstrapProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Drivalry',
      theme: DrivalryTheme.light(),
      darkTheme: DrivalryTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
