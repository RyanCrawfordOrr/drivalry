/// Build-time configuration.
///
/// Values come from `--dart-define-from-file=../.env` (see app/README.md).
/// Nothing here is secret: the Supabase publishable key and the Google Maps
/// key both ship inside the app binary. They are kept out of the repo so the
/// public source cannot be pointed at our project by copy-paste.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  /// Where the phone looks for the speed-limit pack catalogue
  /// (docs/07-pack-format.md §6). Overridable for forks and local testing.
  static const packIndexUrl = String.fromEnvironment(
    'PACK_INDEX_URL',
    defaultValue:
        'https://github.com/RyanCrawfordOrr/drivalry/releases/download/packs-index/index.json',
  );

  /// True when the build was given a Supabase project. Without one the app
  /// runs fully offline: tracking and scoring work, social features show an
  /// explanation instead of failing.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  static bool get hasGoogleMaps => googleMapsApiKey.isNotEmpty;
}
