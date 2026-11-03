import 'dart:io';
import 'dart:typed_data';

import 'package:drivalry/data/garage/documents.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AES-GCM round trip, random IV, tamper detection', () {
    final key = Key.fromSecureRandom(32);
    final plain = Uint8List.fromList(List.generate(5000, (i) => i % 251));
    final blob1 = DocumentVault.encryptBytes(plain, key);
    final blob2 = DocumentVault.encryptBytes(plain, key);
    expect(blob1, isNot(equals(blob2)), reason: 'fresh IV each time');
    expect(
      blob1.length,
      plain.length + DocumentVault.ivLength + DocumentVault.tagLength,
    );
    expect(DocumentVault.decryptBytes(blob1, key), plain);
    expect(DocumentVault.decryptBytes(blob2, key), plain);

    final tampered = Uint8List.fromList(blob1);
    tampered[DocumentVault.ivLength + 3] ^= 0x01;
    expect(() => DocumentVault.decryptBytes(tampered, key), throwsA(anything));
    expect(
      () => DocumentVault.decryptBytes(blob1, Key.fromSecureRandom(32)),
      throwsA(anything),
    );
    expect(
      () => DocumentVault.decryptBytes(Uint8List(4), key),
      throwsFormatException,
    );
    // Flipping a tag byte is caught too.
    final badTag = Uint8List.fromList(blob1);
    badTag[badTag.length - 1] ^= 0x01;
    expect(
      () => DocumentVault.decryptBytes(badTag, key),
      throwsFormatException,
    );
  });

  test('vault creates one key, stores, reads and wipes a file', () async {
    final store = InMemoryVaultKeyStore();
    final vault = DocumentVault(store);
    final dir = await Directory.systemTemp.createTemp('drivalry-vault-');
    addTearDown(() => dir.delete(recursive: true));
    final plain = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]);

    final path = await vault.store(plain, dir, 'doc1');
    expect(store.value, isNotNull);
    final onDisk = await File(path).readAsBytes();
    // Ciphertext is random bytes, so any single value may appear by chance;
    // what must never appear is the plaintext as a run.
    expect(
      containsRun(onDisk, plain),
      isFalse,
      reason: 'plaintext must not be on disk',
    );
    expect(
      onDisk.length,
      plain.length + DocumentVault.ivLength + DocumentVault.tagLength,
    );
    expect(await vault.read(path), plain);

    // A second vault with the same store decrypts; a fresh store cannot.
    expect(await DocumentVault(store).read(path), plain);
    final other = InMemoryVaultKeyStore();
    expect(() => DocumentVault(other).read(path), throwsA(anything));

    await vault.delete(path);
    expect(await File(path).exists(), isFalse);
    await vault.delete(path); // idempotent
  });
}

/// True when [needle] occurs as a contiguous run inside [haystack].
bool containsRun(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
