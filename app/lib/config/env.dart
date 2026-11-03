/// Build-time configuration.
///
/// Values come from `--dart-define-from-file=../.env` (see app/README.md).
/// Nothing here is secret: the Supabase publishable key, the Google Maps key,
/// the OAuth client ids and the Firebase options all ship inside the app
/// binary. They are kept out of the repo so the public source cannot be
/// pointed at our project by copy-paste.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  /// Google sign-in (docs/09-auth-setup.md). The web client id is the
  /// audience every platform's id token is issued to; the iOS client id is
  /// what the iOS SDK presents.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  /// Firebase Cloud Messaging, initialised programmatically so the build
  /// needs no google-services.json (docs/09-auth-setup.md §7).
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseAppIdAndroid = String.fromEnvironment(
    'FIREBASE_APP_ID_ANDROID',
  );
  static const firebaseAppIdIos = String.fromEnvironment('FIREBASE_APP_ID_IOS');

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

  static bool get hasGoogleSignIn => googleWebClientId.isNotEmpty;

  static bool get hasFirebase =>
      firebaseApiKey.isNotEmpty &&
      firebaseProjectId.isNotEmpty &&
      firebaseSenderId.isNotEmpty;
}
