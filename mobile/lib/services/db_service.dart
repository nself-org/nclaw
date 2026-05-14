import 'package:nclaw/src/rust/api/types.dart';

/// DbService wraps Rust core database FFI.
///
/// Migrates from sqflite to sqlite-vec via Rust core.
/// Stub: FFI calls wired on first `make codegen` run + S15.T18 mobile FFI integration.
class DbService {
  /// Initialize database connection.
  ///
  /// Calls Rust: nclaw_init_db(db_path)
  Future<void> initialize({required String dbPath}) async {
    // Stub: FFI call pending codegen
    // await api.initDb(dbPath: dbPath);
  }

  /// Store a message in local sqlite-vec.
  ///
  /// Calls Rust: nclaw_db_insert_message(message)
  Future<void> storeMessage(Message msg) async {
    // Stub: FFI call pending codegen
    // await api.dbInsertMessage(message: msg);
  }

  /// Retrieve messages by topic.
  ///
  /// Calls Rust: nclaw_db_query_by_topic(topic)
  Future<List<Message>> queryByTopic(String topic) async {
    // Stub: FFI call pending codegen
    // return await api.dbQueryByTopic(topic: topic);
    return [];
  }

  /// Retrieve messages by vector similarity.
  ///
  /// Calls Rust: nclaw_db_vector_search(embedding, limit)
  Future<List<Message>> vectorSearch(List<double> embedding, {int limit = 10}) async {
    // Stub: FFI call pending codegen
    // return await api.dbVectorSearch(embedding: embedding, limit: limit);
    return [];
  }

  /// Clear database (for testing).
  Future<void> clear() async {
    // Stub: FFI call pending codegen
    // await api.dbClear();
  }
}
