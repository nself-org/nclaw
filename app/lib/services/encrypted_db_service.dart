/// S22-T05: Encrypted SQLite backing store.
///
/// Wraps sqflite_sqlcipher with a passphrase that is generated once per
/// install and stored in the platform keychain (Keychain on iOS / macOS,
/// Keystore-backed EncryptedSharedPreferences on Android) via
/// flutter_secure_storage.
///
/// On platforms where SQLCipher is unavailable (desktop test / web), the
/// service transparently falls back to plain sqflite. This keeps
/// `flutter test` green on CI while still encrypting production mobile
/// builds.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as plain;
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
  /// dir). Falls back to plain sqflite on unsupported platforms.
  ///
  /// Callers receive a dynamic Database handle — both plugins expose the
  /// same query/execute/insert API surface, so call-sites stay identical.
  static Future<OpenedDatabase> open(
    String filename, {
    required int version,
    required Future<void> Function(dynamic db, int version) onCreate,
    Future<void> Function(dynamic db, int oldVersion, int newVersion)?
        onUpgrade,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, filename);

    if (!_shouldEncrypt) {
      final db = await plain.openDatabase(
        path,
        version: version,
        onCreate: (d, v) async => await onCreate(d, v),
        onUpgrade: onUpgrade == null
            ? null
            : (d, o, n) async => await onUpgrade(d, o, n),
      );
      return OpenedDatabase._(db, encrypted: false);
    }

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
