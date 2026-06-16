/// S22-T05: Encrypted SQLite backing store.
///
/// Wraps sqflite_sqlcipher with a passphrase that is generated once per
/// install and stored in the platform keychain (Keychain on iOS / macOS,
/// Keystore-backed EncryptedSharedPreferences on Android) via
/// flutter_secure_storage.
///
/// Supported platforms: iOS, Android, macOS only.
///
/// On unsupported platforms (Linux, Windows, web), [open] throws
/// [UnsupportedError] rather than silently falling back to plaintext.
/// See `mobile/docs/platform-encryption-matrix.md` for the full matrix.
///
/// Tests that need a database handle on unsupported platforms must use
/// the dedicated in-memory plain sqflite test harness (see `test/`) and
/// explicitly opt out of encryption — production code paths must not
/// silently downgrade.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

class EncryptedDbService {
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const _passphraseKey = 'nclaw.db.passphrase.v1';

  /// Whether SQLCipher is supported on this platform. Desktop (Linux / Windows)
  /// and web builds use plain sqflite.
  static bool get _shouldEncrypt {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  /// Returns (or lazily generates + persists) the database passphrase.
  /// 32 bytes of cryptographically-random data, base64-encoded.
  static Future<String> _getOrCreatePassphrase() async {
    final existing = await _secureStorage.read(key: _passphraseKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    final pass = base64Encode(bytes);
    await _secureStorage.write(key: _passphraseKey, value: pass);
    return pass;
  }

  /// Opens an encrypted database at [filename] (relative to app documents
  /// dir).
  ///
  /// Throws [UnsupportedError] on Linux, Windows, and web — those platforms
  /// have no SQLCipher backend in this build. Production code MUST NOT
  /// downgrade to plaintext sqflite silently; the caller must explicitly
  /// pick a different storage path (e.g. an in-memory test harness) when
  /// running on an unsupported platform.
  ///
  /// Callers receive a dynamic Database handle from sqflite_sqlcipher.
  static Future<OpenedDatabase> open(
    String filename, {
    required int version,
    required Future<void> Function(dynamic db, int version) onCreate,
    Future<void> Function(dynamic db, int oldVersion, int newVersion)?
        onUpgrade,
  }) async {
    if (!_shouldEncrypt) {
      throw UnsupportedError(
        'Encrypted database is not available on '
        '${kIsWeb ? "web" : defaultTargetPlatform}. '
        'SQLCipher is only enabled on iOS, Android, and macOS in v1.1.x. '
        'See mobile/docs/platform-encryption-matrix.md for the full matrix.',
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, filename);

    final passphrase = await _getOrCreatePassphrase();
    final db = await cipher.openDatabase(
      path,
      password: passphrase,
      version: version,
      onCreate: (d, v) async => await onCreate(d, v),
      onUpgrade: onUpgrade == null
          ? null
          : (d, o, n) async => await onUpgrade(d, o, n),
    );
    return OpenedDatabase._(db, encrypted: true);
  }
}

/// Thin handle that hides whether the underlying Database is SQLCipher-backed
/// or plain sqflite. Both packages expose the same Database API surface
/// (execute, query, insert, etc.), so callers use dynamic dispatch.
class OpenedDatabase {
  final dynamic db;
  final bool encrypted;
  const OpenedDatabase._(this.db, {required this.encrypted});
}
