import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

/// Where the vault's 256-bit key lives. The real one is the OS keychain /
/// keystore through flutter_secure_storage; tests use memory.
abstract class VaultKeyStore {
  Future<String?> read();
  Future<void> write(String base64Key);
}

class SecureVaultKeyStore implements VaultKeyStore {
  SecureVaultKeyStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'doc_vault_key';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String base64Key) =>
      _storage.write(key: _key, value: base64Key);
}

class InMemoryVaultKeyStore implements VaultKeyStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String base64Key) async => value = base64Key;
}

/// Encrypts vehicle documents (insurance card, registration) at rest.
///
/// Encrypt-then-MAC: AES-256-CTR under a random 16-byte IV, then HMAC-SHA256
/// over `IV || ciphertext` with a key derived from the master key. The file is
/// `IV(16) || ciphertext || tag(32)`. Any change to the file fails the tag
/// check before decryption. Nothing here ever leaves the phone (docs/01 §4.7).
class DocumentVault {
  DocumentVault(this.keyStore);

  final VaultKeyStore keyStore;
  Key? _cached;

  static const int ivLength = 16;
  static const int tagLength = 32;

  Future<Key> _key() async {
    final cached = _cached;
    if (cached != null) return cached;
    final stored = await keyStore.read();
    if (stored != null && stored.isNotEmpty) {
      return _cached = Key.fromBase64(stored);
    }
    final fresh = Key.fromSecureRandom(32);
    await keyStore.write(fresh.base64);
    return _cached = fresh;
  }

  static Hmac _mac(Key key) => Hmac(
    sha256,
    sha256.convert([...key.bytes, ...'drivalry-doc-mac'.codeUnits]).bytes,
  );

  /// Pure: encrypts [plain] with [key] under a fresh random IV and tags it.
  static Uint8List encryptBytes(Uint8List plain, Key key, {IV? iv}) {
    final nonce = iv ?? IV.fromSecureRandom(ivLength);
    final encrypter = Encrypter(AES(key, mode: AESMode.ctr, padding: null));
    final cipher = encrypter.encryptBytes(plain, iv: nonce).bytes;
    final body = Uint8List(ivLength + cipher.length);
    body.setRange(0, ivLength, nonce.bytes);
    body.setRange(ivLength, body.length, cipher);
    final tag = _mac(key).convert(body).bytes;
    final out = Uint8List(body.length + tagLength);
    out.setRange(0, body.length, body);
    out.setRange(body.length, out.length, tag);
    return out;
  }

  /// Pure: reverses [encryptBytes]. Throws on a wrong key or tampered data.
  static Uint8List decryptBytes(Uint8List blob, Key key) {
    if (blob.length < ivLength + tagLength) {
      throw const FormatException('document blob too short');
    }
    final body = Uint8List.sublistView(blob, 0, blob.length - tagLength);
    final tag = Uint8List.sublistView(blob, blob.length - tagLength);
    final expected = _mac(key).convert(body).bytes;
    var diff = 0;
    for (var i = 0; i < tagLength; i++) {
      diff |= expected[i] ^ tag[i];
    }
    if (diff != 0) throw const FormatException('document tag mismatch');
    final nonce = IV(Uint8List.sublistView(body, 0, ivLength));
    final cipher = Uint8List.sublistView(body, ivLength);
    final encrypter = Encrypter(AES(key, mode: AESMode.ctr, padding: null));
    return Uint8List.fromList(
      encrypter.decryptBytes(Encrypted(cipher), iv: nonce),
    );
  }

  /// Writes an encrypted copy of [plain] as `<dir>/<id>.bin` and returns the
  /// path. The directory is created if needed.
  Future<String> store(Uint8List plain, Directory dir, String id) async {
    await dir.create(recursive: true);
    final key = await _key();
    final path = p.join(dir.path, '$id.bin');
    await File(path).writeAsBytes(encryptBytes(plain, key), flush: true);
    return path;
  }

  Future<Uint8List> read(String path) async {
    final key = await _key();
    final blob = await File(path).readAsBytes();
    return decryptBytes(blob, key);
  }

  /// Overwrites the file with zeros before deleting it, so a casual file
  /// recovery finds nothing readable.
  Future<void> delete(String path) async {
    final f = File(path);
    if (!await f.exists()) return;
    try {
      final len = await f.length();
      await f.writeAsBytes(Uint8List(len), flush: true);
    } finally {
      await f.delete();
    }
  }
}
