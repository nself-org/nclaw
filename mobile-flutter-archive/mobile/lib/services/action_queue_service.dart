import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/claw_action.dart';

/// Local SQLite-backed action queue for offline persistence.
///
/// Actions received via WebSocket are stored here so they survive app restarts
/// and network interruptions. On reconnect, pending actions can be drained
/// and sent back to the server.
class ActionQueueService {
  Database? _db;
  final _changeController = StreamController<void>.broadcast();

  /// Fires whenever the action table changes (insert, update, delete).
  Stream<void> get onChange => _changeController.stream;

  /// Initialize the SQLite database.
  Future<void> init() async {
    if (_db != null) return;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'nclaw_actions.db');

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE actions (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            type TEXT NOT NULL,
            params TEXT NOT NULL DEFAULT '{}',
            status TEXT NOT NULL DEFAULT 'pending',
            result TEXT,
            created_at TEXT NOT NULL,
            executed_at TEXT,
            expires_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_actions_status ON actions(status)',
        );
        await db.execute(
          'CREATE INDEX idx_actions_created ON actions(created_at)',
        );
      },
    );
  }

  /// Insert a new action into the queue. Ignores duplicates by id.
  Future<void> enqueue(ClawAction action) async {
    final db = _requireDb();
    await db.insert(
      'actions',
      action.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    _changeController.add(null);
  }

  /// Update the status (and optionally result/executedAt) of an action.
  Future<void> updateStatus(
    String actionId,
    ActionStatus status, {
    Map<String, dynamic>? result,
  }) async {
    final db = _requireDb();
    final values = <String, dynamic>{'status': status.toJson()};
    if (result != null) {
      values['result'] = result.toString();
    }
    if (status == ActionStatus.executing ||
        status == ActionStatus.done ||
        status == ActionStatus.failed) {
      values['executed_at'] = DateTime.now().toIso8601String();
    }

    await db.update(
      'actions',
      values,
      where: 'id = ?',
      whereArgs: [actionId],
    );
    _changeController.add(null);
  }

  /// Get all actions matching the given statuses, ordered by creation time.
  Future<List<ClawAction>> getByStatus(List<ActionStatus> statuses) async {
    final db = _requireDb();
    final placeholders = statuses.map((_) => '?').join(',');
    final rows = await db.query(
      'actions',
      where: 'status IN ($placeholders)',
      whereArgs: statuses.map((s) => s.toJson()).toList(),
      orderBy: 'created_at DESC',
    );
    return rows.map(ClawAction.fromMap).toList();
  }

  /// Get a single action by id.
  Future<ClawAction?> getById(String actionId) async {
    final db = _requireDb();
    final rows = await db.query(
      'actions',
      where: 'id = ?',
      whereArgs: [actionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ClawAction.fromMap(rows.first);
  }

  /// Get all pending actions that should be drained on reconnect.
  Future<List<ClawAction>> getPending() async {
    return getByStatus([ActionStatus.pending]);
  }

  /// Get all actions (for the history view), most recent first.
  Future<List<ClawAction>> getAll() async {
    final db = _requireDb();
    final rows = await db.query('actions', orderBy: 'created_at DESC');
    return rows.map(ClawAction.fromMap).toList();
  }

  /// Count actions by status.
  Future<int> countByStatus(ActionStatus status) async {
    final db = _requireDb();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM actions WHERE status = ?',
      [status.toJson()],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Expire old pending actions (older than 24 hours).
  Future<int> expireOldActions() async {
    final db = _requireDb();
    final cutoff =
        DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();
    final count = await db.update(
      'actions',
      {'status': ActionStatus.expired.toJson()},
      where: 'status = ? AND expires_at < ?',
      whereArgs: [ActionStatus.pending.toJson(), cutoff],
    );
    if (count > 0) {
      _changeController.add(null);
    }
    return count;
  }

  /// Delete all actions in terminal states older than 7 days.
  Future<int> pruneHistory() async {
    final db = _requireDb();
    final cutoff =
        DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
    final count = await db.delete(
      'actions',
      where: 'status IN (?, ?, ?) AND created_at < ?',
      whereArgs: [
        ActionStatus.done.toJson(),
        ActionStatus.failed.toJson(),
        ActionStatus.expired.toJson(),
        cutoff,
      ],
    );
    if (count > 0) {
      _changeController.add(null);
    }
    return count;
  }

  /// Close the database.
  Future<void> dispose() async {
    await _changeController.close();
    await _db?.close();
    _db = null;
  }

  Database _requireDb() {
    final db = _db;
    if (db == null) {
      throw StateError(
        'ActionQueueService not initialized. Call init() first.',
      );
    }
    return db;
  }
}
