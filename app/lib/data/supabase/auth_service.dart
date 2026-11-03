import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/env.dart';
import '../db/database.dart';
import '../push/push_service.dart';
import '../repos/presence_repo.dart';
import 'supabase_providers.dart';

/// A sign-in that did not produce a session. [cancelled] is true when the
/// user dismissed the sheet, which the UI shows as nothing at all.
class SignInFailure implements Exception {
  const SignInFailure(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;
  @override
  String toString() => 'SignInFailure($message)';
}

/// Tokens from a native identity provider, ready for Supabase.
class IdTokens {
  const IdTokens({
    required this.idToken,
    this.accessToken,
    this.nonce,
    this.fullName,
  });
  final String idToken;
  final String? accessToken;

  /// The raw nonce whose SHA-256 was sent to the provider (Apple).
  final String? nonce;

  /// Only on the very first Apple sign-in, when Apple shares the name.
  final String? fullName;
}

/// Native Google sign-in, wrapped so tests can substitute it.
abstract class GoogleIdTokenProvider {
  Future<IdTokens> signIn();
  Future<void> signOut();
}

/// Native Sign in with Apple, wrapped so tests can substitute it.
abstract class AppleIdTokenProvider {
  Future<IdTokens> signIn(String rawNonce);
}

/// The real google_sign_in v7 flow.
class GoogleSignInProvider implements GoogleIdTokenProvider {
  bool _initialised = false;

  Future<void> _init() async {
    if (_initialised) return;
    await GoogleSignIn.instance.initialize(
      clientId: Platform.isIOS && Env.googleIosClientId.isNotEmpty
          ? Env.googleIosClientId
          : null,
      serverClientId: Env.googleWebClientId,
    );
    _initialised = true;
  }

  @override
  Future<IdTokens> signIn() async {
    await _init();
    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: const ['email', 'profile'],
    );
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const SignInFailure('Google did not return an identity token.');
    }
    String? accessToken;
    try {
      final auth = await account.authorizationClient.authorizationForScopes(
        const ['email', 'profile'],
      );
      accessToken = auth?.accessToken;
    } catch (_) {
      // Optional: Supabase accepts the id token alone.
    }
    return IdTokens(
      idToken: idToken,
      accessToken: accessToken,
      fullName: account.displayName,
    );
  }

  @override
  Future<void> signOut() async {
    if (!_initialised) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}

/// The real sign_in_with_apple flow (iOS only).
class AppleSignInProvider implements AppleIdTokenProvider {
  @override
  Future<IdTokens> signIn(String rawNonce) async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: AuthService.sha256Hex(rawNonce),
    );
    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const SignInFailure('Apple did not return an identity token.');
    }
    final name = [
      credential.givenName,
      credential.familyName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return IdTokens(
      idToken: idToken,
      nonce: rawNonce,
      fullName: name.isEmpty ? null : name,
    );
  }
}

/// Sign in, sign out, delete, export (docs/09-auth-setup.md, docs/06 M2.1).
class AuthService {
  AuthService(
    this._client, {
    GoogleIdTokenProvider? google,
    AppleIdTokenProvider? apple,
    Random? random,
    this.beforeSignOut,
    this.afterSignOut,
  }) : _google = google ?? GoogleSignInProvider(),
       _apple = apple ?? AppleSignInProvider(),
       _random = random ?? Random.secure();

  final SupabaseClient? _client;
  final GoogleIdTokenProvider _google;
  final AppleIdTokenProvider _apple;
  final Random _random;

  /// Runs before the session is dropped (push token removal, presence row).
  final Future<void> Function()? beforeSignOut;

  /// Runs after the session is gone (forget per-account upload state so a
  /// different account on this phone starts clean).
  final Future<void> Function()? afterSignOut;

  /// Apple is offered on iOS only (docs/09 §0).
  static bool get appleAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get googleAvailable => Env.hasGoogleSignIn;

  SupabaseClient get _c {
    final c = _client;
    if (c == null) {
      throw const SignInFailure(
        'This build has no Drivalry cloud project configured.',
      );
    }
    return c;
  }

  Future<void> signInWithGoogle() async {
    if (!Env.hasGoogleSignIn) {
      throw const SignInFailure(
        'Google sign-in is not configured for this build.',
      );
    }
    final client = _c;
    final IdTokens tokens;
    try {
      tokens = await _google.signIn();
    } on SignInFailure {
      rethrow;
    } catch (e) {
      final mapped = mapGoogleError(e);
      throw SignInFailure(mapped.$1, cancelled: mapped.$2);
    }
    try {
      await client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      );
    } on AuthException catch (e) {
      throw SignInFailure(mapAuthError(e));
    }
  }

  Future<void> signInWithApple() async {
    final client = _c;
    final rawNonce = generateNonce(_random);
    final IdTokens tokens;
    try {
      tokens = await _apple.signIn(rawNonce);
    } on SignInFailure {
      rethrow;
    } catch (e) {
      final mapped = mapAppleError(e);
      throw SignInFailure(mapped.$1, cancelled: mapped.$2);
    }
    try {
      await client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: tokens.idToken,
        nonce: tokens.nonce,
      );
    } on AuthException catch (e) {
      throw SignInFailure(mapAuthError(e));
    }
    final name = tokens.fullName;
    final uid = client.auth.currentUser?.id;
    if (name != null && uid != null) {
      // Apple only shares the name once; keep it.
      try {
        await client
            .from('profiles')
            .update({'display_name': name})
            .eq('id', uid);
      } catch (_) {}
    }
  }

  Future<void> signOut() async {
    final client = _client;
    if (client == null) return;
    try {
      await beforeSignOut?.call();
    } catch (_) {}
    await _google.signOut();
    await client.auth.signOut();
    await afterSignOut?.call();
  }

  /// Deletes the account server-side (cascades through every table), then
  /// signs out and drops the local cloud cache. Local trips stay.
  Future<void> deleteAccount(AppDatabase db) async {
    final client = _c;
    await client.rpc('delete_own_account');
    try {
      await beforeSignOut?.call();
    } catch (_) {}
    await _google.signOut();
    try {
      await client.auth.signOut();
    } catch (_) {
      // The user no longer exists; a failed sign-out is expected.
    }
    await db.resetAccountState();
    await afterSignOut?.call();
  }

  /// Writes everything this phone knows about the user's own driving to a
  /// JSON file in the temp directory and opens the share sheet. The user
  /// chose to export, so routes are included.
  Future<File> exportMyData(AppDatabase db, {String? profileJson}) async {
    final trips = await db.watchRecentTrips(limit: 100000).first;
    final out = <String, Object?>{
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'app': 'Drivalry',
      if (profileJson != null) 'profile': jsonDecode(profileJson),
      'trips': [
        for (final t in trips)
          {
            'trip': _tripJson(t.trip),
            if (t.score != null) 'score': jsonDecode(t.score!.scoreJson),
            'segments': [
              for (final s in await db.segmentsFor(t.trip.id)) s.toJson(),
            ],
            'samples': [
              for (final s in await db.samplesFor(t.trip.id))
                {
                  't': s.t,
                  'lat': s.lat,
                  'lon': s.lon,
                  'speed': s.speed,
                  'accuracy': s.accuracy,
                  'heading': s.heading,
                  'altitude': s.altitude,
                },
            ],
          },
      ],
    };
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}drivalry-export-'
      '${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(jsonEncode(out));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Drivalry export',
      ),
    );
    return file;
  }

  static Map<String, Object?> _tripJson(Trip t) => {
    'id': t.id,
    'startedAt': t.startedAt,
    'endedAt': t.endedAt,
    'phase': t.phase,
    'endReason': t.endReason,
    'distanceM': t.distanceM,
    'movingS': t.movingS,
    'isPassenger': t.isPassenger,
    'vehicleLabel': t.vehicleLabel,
    'packRegion': t.packRegion,
    'limitCoverage': t.limitCoverage,
    'nightFraction': t.nightFraction,
    'weather': t.weather,
  };

  // ------------------------------------------------------------ helpers --

  /// URL-safe random nonce for Sign in with Apple.
  static String generateNonce(Random random, [int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    return String.fromCharCodes(
      List.generate(
        length,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  static String sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  /// (message, cancelled) for a google_sign_in failure.
  static (String, bool) mapGoogleError(Object e) {
    if (e is GoogleSignInException) {
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
          return ('Sign-in cancelled.', true);
        case GoogleSignInExceptionCode.interrupted:
          return ('Google sign-in was interrupted. Try again.', false);
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          return ('Google sign-in is not configured for this build.', false);
        case GoogleSignInExceptionCode.uiUnavailable:
          return ('Google sign-in is not available right now.', false);
        case GoogleSignInExceptionCode.userMismatch:
          return ('Google returned a different account than expected.', false);
        case GoogleSignInExceptionCode.unknownError:
          break;
      }
      final d = e.description ?? '';
      if (d.contains('10') || d.toUpperCase().contains('DEVELOPER_ERROR')) {
        return ('Google sign-in is not configured for this build.', false);
      }
      return ('Google sign-in failed: ${d.isEmpty ? e.code.name : d}', false);
    }
    final s = e.toString();
    if (s.contains('network') || s.contains('SocketException')) {
      return ('No connection. Check your network and try again.', false);
    }
    return ('Google sign-in failed.', false);
  }

  /// (message, cancelled) for a sign_in_with_apple failure.
  static (String, bool) mapAppleError(Object e) {
    if (e is SignInWithAppleAuthorizationException) {
      switch (e.code) {
        case AuthorizationErrorCode.canceled:
          return ('Sign-in cancelled.', true);
        case AuthorizationErrorCode.notHandled:
        case AuthorizationErrorCode.notInteractive:
          return ('Apple sign-in could not start. Try again.', false);
        case AuthorizationErrorCode.invalidResponse:
        case AuthorizationErrorCode.failed:
        case AuthorizationErrorCode.unknown:
          return ('Apple sign-in failed: ${e.message}', false);
        case AuthorizationErrorCode.credentialExport:
        case AuthorizationErrorCode.credentialImport:
        case AuthorizationErrorCode.matchedExcludedCredential:
          return ('Apple sign-in failed: ${e.message}', false);
      }
    }
    if (e is SignInWithAppleNotSupportedException) {
      return ('Sign in with Apple needs iOS 13 or newer.', false);
    }
    return ('Apple sign-in failed.', false);
  }

  /// A Supabase auth error, in words.
  static String mapAuthError(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('unsupported provider') ||
        m.contains('provider is not enabled')) {
      return 'This sign-in method is not enabled yet. Ask the app owner to '
          'finish docs/09-auth-setup.md.';
    }
    if (m.contains('audience') || m.contains('aud')) {
      return 'The sign-in token was issued for a different client id. Check '
          'the Supabase authorized client ids.';
    }
    if (m.contains('nonce')) {
      return 'Sign-in token nonce mismatch. Try again.';
    }
    if (m.contains('signups not allowed')) {
      return 'New accounts are closed right now.';
    }
    return 'Sign-in failed: ${e.message}';
  }
}

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    ref.watch(supabaseProvider),
    // While the session still exists: drop this device's push token and the
    // presence row, so a signed-out phone is neither notified nor shown.
    beforeSignOut: () async {
      await ref.read(pushControllerProvider.notifier).unregister();
      final uid = ref.read(currentUserIdProvider);
      final presence = ref.read(presenceRepoProvider);
      if (uid != null && presence != null) {
        try {
          await presence.clear(uid);
        } catch (_) {}
      }
    },
    // Afterwards: forget upload records, badge sync marks, the outbox and
    // cached reads, so another account on this phone uploads afresh.
    afterSignOut: () => ref.read(databaseProvider).resetAccountState(),
  ),
);
