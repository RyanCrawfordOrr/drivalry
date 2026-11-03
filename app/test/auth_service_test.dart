import 'dart:math';

import 'package:drivalry/data/supabase/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('nonce', () {
    test('is URL-safe and the requested length', () {
      final n = AuthService.generateNonce(Random(1));
      expect(n.length, 32);
      expect(RegExp(r'^[0-9A-Za-z\-._]+$').hasMatch(n), isTrue);
      expect(AuthService.generateNonce(Random(1), 8).length, 8);
    });

    test('sha256Hex matches a known vector', () {
      expect(
        AuthService.sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('Google error mapping', () {
    test('cancel is silent', () {
      final (msg, cancelled) = AuthService.mapGoogleError(
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
      );
      expect(cancelled, isTrue);
      expect(msg, isNotEmpty);
    });

    test('configuration errors name the build', () {
      for (final code in [
        GoogleSignInExceptionCode.clientConfigurationError,
        GoogleSignInExceptionCode.providerConfigurationError,
      ]) {
        final (msg, cancelled) = AuthService.mapGoogleError(
          GoogleSignInException(code: code),
        );
        expect(cancelled, isFalse);
        expect(msg, 'Google sign-in is not configured for this build.');
      }
    });

    test('DEVELOPER_ERROR (code 10) is a configuration problem', () {
      final (msg, _) = AuthService.mapGoogleError(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'DEVELOPER_ERROR: 10',
        ),
      );
      expect(msg, 'Google sign-in is not configured for this build.');
    });

    test('unknown errors keep the description', () {
      final (msg, _) = AuthService.mapGoogleError(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: 'something odd',
        ),
      );
      expect(msg, contains('something odd'));
    });

    test('network failures are explained', () {
      final (msg, _) = AuthService.mapGoogleError(
        Exception('SocketException: Failed host lookup'),
      );
      expect(msg, contains('connection'));
    });
  });

  group('Apple error mapping', () {
    test('cancel is silent', () {
      final (_, cancelled) = AuthService.mapAppleError(
        const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.canceled,
          message: 'cancelled',
        ),
      );
      expect(cancelled, isTrue);
    });

    test('failures carry the message', () {
      final (msg, cancelled) = AuthService.mapAppleError(
        const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.failed,
          message: 'boom',
        ),
      );
      expect(cancelled, isFalse);
      expect(msg, contains('boom'));
    });

    test('unsupported platform', () {
      final (msg, _) = AuthService.mapAppleError(
        const SignInWithAppleNotSupportedException(message: 'old iOS'),
      );
      expect(msg, contains('iOS 13'));
    });
  });

  group('Supabase auth error mapping', () {
    test('provider not enabled points at the setup doc', () {
      expect(
        AuthService.mapAuthError(
          const AuthException('Unsupported provider: provider is not enabled'),
        ),
        contains('docs/09'),
      );
    });

    test('audience mismatch names the client ids', () {
      expect(
        AuthService.mapAuthError(const AuthException('Invalid aud claim')),
        contains('client id'),
      );
    });

    test('other errors pass through', () {
      expect(
        AuthService.mapAuthError(const AuthException('rate limited')),
        'Sign-in failed: rate limited',
      );
    });
  });
}
