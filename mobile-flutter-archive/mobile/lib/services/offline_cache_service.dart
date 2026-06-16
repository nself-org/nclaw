/// E-26-08b: Offline cache service using sqflite/drift.
///
/// Local SQLite database for caching conversations, memories, and topics.
/// Write queue for pending operations. Sync on reconnect.
import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class OfflineCacheService {
  static OfflineCacheService? _instance;
  Database? _db;

  OfflineCacheService._();

  static OfflineCacheService get instance {
    _instance ??= OfflineCacheService._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'nclaw_cache.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Conversations cache.
        await db.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

        // Messages cache.
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            data TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');

        // Topics cache.
        await db.execute('''
          CREATE TABLE topics (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

        // Memories cache.
        await db.execute('''
          CREATE TABLE memories (
            id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL,
            data TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

        // Write queue for pending operations.
        await db.execute('''
          CREATE TABLE write_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            endpoint TEXT NOT NULL,
            method TEXT NOT NULL,
            body TEXT,
            created_at TEXT NOT NULL,
            status TEXT DEFAULT 'pending'
          )
        ''');
      },
    );
  }

  // -- Conversations ---------------------------------------------------------

  Future<void> cacheConversation(String id, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'conversations',
      {
        'id': id,
        'data': jsonEncode(data),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getCachedConversations() async {
    final db = await database;
    final rows = await db.query('conversations', orderBy: 'updated_at DESC');
    return rows
        .map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>)
        .toList();
  }

  // -- Messages --------------------------------------------------------------

  Future<void> cacheMessage(
      String id, String conversationId, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'messages',
      {
        'id': id,
        'conversation_id': conversationId,
        'data': jsonEncode(data),
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getCachedMessages(
      String conversationId) async {
    final db = await database;
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>)
        .toList();
  }

  // -- Topics ----------------------------------------------------------------

  Future<void> cacheTopics(List<Map<String, dynamic>> topics) async {
    final db = await database;
    final batch = db.batch();
    for (final topic in topics) {
      batch.insert(
        'topics',
        {
          'id': topic['id'] as String,
          'data': jsonEncode(topic),
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedTopics() async {
    final db = await database;
    final rows = await db.query('topics');
    return rows
        .map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>)
        .toList();
  }

  // -- Memories --------------------------------------------------------------

  Future<void> cacheMemories(List<Map<String, dynamic>> memories) async {
    final db = await database;
    final batch = db.batch();
    for (final memory in memories) {
      batch.insert(
        'memories',
        {
          'id': memory['id'] as String,
          'entity_type': memory['entity_type'] as String? ?? 'fact',
          'data': jsonEncode(memory),
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedMemories(
      {String? entityType}) async {
    final db = await database;
    final rows = entityType != null
        ? await db.query('memories',
            where: 'entity_type = ?', whereArgs: [entityType])
        : await db.query('memories');
    return rows
        .map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>)
        .toList();
  }

  // -- Write Queue -----------------------------------------------------------

  Future<void> enqueueWrite({
    required String endpoint,
    required String method,
    String? body,
  }) async {
    final db = await database;
    await db.insert('write_queue', {
      'endpoint': endpoint,
      'method': method,
      'body': body,
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pending',
    });
  }

  Future<List<Map<String, dynamic>>> getPendingWrites() async {
    final db = await database;
    return db.query('write_queue',
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'created_at ASC');
  }

  Future<void> markWriteComplete(int id) async {
    final db = await database;
    await db.update(
      'write_queue',
      {'status': 'complete'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markWriteFailed(int id) async {
    final db = await database;
    await db.update(
      'write_queue',
      {'status': 'failed'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> pendingWriteCount() async {
    final db = await database;
    final result = await db
        .rawQuery("SELECT COUNT(*) as cnt FROM write_queue WHERE status = 'pending'");
    return (result.first['cnt'] as int?) ?? 0;
  }

  // -- Cleanup ---------------------------------------------------------------

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('conversations');
    await db.delete('messages');
    await db.delete('topics');
    await db.delete('memories');
    await db.delete('write_queue');
  }
}
