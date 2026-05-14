import 'package:nclaw/src/rust/api/types.dart';
import 'db_service.dart';

/// MigrationService — S20.T11 v1.1.0 → v1.1.1 mobile data migration.
///
/// Detects v1.1.0 sqflite DB, exports rows, re-imports into Rust-side sqlite-vec.
class MigrationService {
  final _dbService = DbService();

  /// Check if migration from v1.1.0 is needed.
  ///
  /// Returns true if v1.1.0 sqflite DB is detected.
  Future<bool> needsMigration() async {
    // Stub: detects presence of v1.1.0 sqflite db at known path
    // if (File('${dbPath}/messages.db').existsSync()) return true;
    return false;
  }

  /// Execute migration: read old sqflite rows, insert into sqlite-vec via Rust.
  ///
  /// Calls Rust: nclaw_db_insert_message for each migrated row.
  Future<void> migrate() async {
    if (!await needsMigration()) return;

    try {
      // Stub: read rows from old sqflite db
      // final oldMessages = await _readOldDb();
      // for (final msg in oldMessages) {
      //   await _dbService.storeMessage(msg);
      // }
    } catch (e) {
      rethrow;
    }
  }

  /// Mark migration as complete (persists in vault).
  Future<void> markComplete() async {
    // Stub: call vault to persist migration flag
    // await _vaultService.set('migration_v1_1_0_complete', 'true');
  }

  /// Stub: read old sqflite rows (implements in v1.1.1).
  Future<List<Message>> _readOldDb() async {
    // Stub: sqflite migration logic
    return [];
  }
}
