import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'data/supabase/supabase_providers.dart';
import 'features/convoy/audio/convoy_audio_session.dart';
import 'features/convoy/radio/radio_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(
    ProviderScope(
      overrides: [
        // The radio drives the platform audio session (foreground service on
        // Android, AVAudioSession on iOS) through the native plugin.
        convoyAudioSessionHookProvider.overrideWith(
          (ref) => ref.watch(nativeAudioSessionHookProvider),
        ),
      ],
      child: const DrivalryApp(),
    ),
  );
}
