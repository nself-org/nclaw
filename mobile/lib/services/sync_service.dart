import 'package:nclaw/src/rust/api/types.dart';

/// SyncService wraps Rust core sync FFI.
///
/// Handles bidirectional sync between local state and server.
/// Stub: FFI calls wired on first `make codegen` run + S15.T18 mobile FFI integration.
class SyncService {
  /// Initialize sync engine with server details.
  ///
  /// Calls Rust: nclaw_init_sync(server_url, jwt)
  Future<void> initialize({
    required String serverUrl,
    required String jwt,
  }) async {
    // Stub: FFI call pending codegen
    // final result = await api.initSync(serverUrl: serverUrl, jwt: jwt);
  }

  /// Push local events to server.
  ///
  /// Calls Rust: nclaw_sync_push(events)
  Future<void> push(List<Message> events) async {
    // Stub: FFI call pending codegen
    // await api.syncPush(events: events);
  }

  /// Pull remote changes since cursor.
  ///
  /// Calls Rust: nclaw_sync_pull(cursor) → returns Rust-backed Messages
  Future<List<Message>> pull(String sinceCursor) async {
    // Stub: FFI call pending codegen
    // return await api.syncPull(cursor: sinceCursor);
    return [];
  }

  /// Acknowledge received events (server-side cleanup).
  Future<void> ack(List<String> eventIds) async {
    // Stub: FFI call pending codegen
    // await api.syncAck(eventIds: eventIds);
  }
}
