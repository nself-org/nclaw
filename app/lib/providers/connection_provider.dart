import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/claw_action.dart';
import '../models/server_config.dart';
import '../services/action_queue_service.dart';
import '../services/claw_client.dart';
import 'action_provider.dart';

/// Keys used in secure storage.
class StorageKeys {
  static const servers = 'nclaw_servers';
  static const activeServerId = 'nclaw_active_server_id';
}

/// WebSocket connection status mirrored from ClawClient for UI consumption.
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Combined state for the connection provider.
class ConnectionState {
  final List<ServerConfig> servers;
  final String? activeServerId;
  final ConnectionStatus status;
  final String? errorMessage;

  const ConnectionState({
    this.servers = const [],
    this.activeServerId,
    this.status = ConnectionStatus.disconnected,
    this.errorMessage,
  });

  /// The currently active server, if any.
  ServerConfig? get activeServer {
    if (activeServerId == null) return null;
    try {
      return servers.firstWhere((s) => s.id == activeServerId);
    } catch (_) {
      return null;
    }
  }

  /// Whether any server is paired.
  bool get hasPairedServers => servers.isNotEmpty;

  ConnectionState copyWith({
    List<ServerConfig>? servers,
    String? activeServerId,
    ConnectionStatus? status,
    String? errorMessage,
    bool clearError = false,
    bool clearActiveServer = false,
  }) {
    return ConnectionState(
      servers: servers ?? this.servers,
      activeServerId:
          clearActiveServer ? null : (activeServerId ?? this.activeServerId),
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Manages multi-server connections, persists to secure storage,
/// and drives the ClawClient WebSocket lifecycle.
class ConnectionNotifier extends StateNotifier<ConnectionState> {
  final FlutterSecureStorage _storage;
  final ClawClient _client;
  final ActionQueueService? _actionQueue;
  StreamSubscription<ClawConnectionStatus>? _statusSub;
  StreamSubscription<Map<String, dynamic>>? _actionSub;

  ConnectionNotifier({
    FlutterSecureStorage? storage,
    ClawClient? client,
    ActionQueueService? actionQueue,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _client = client ?? ClawClient(),
        _actionQueue = actionQueue,
        super(const ConnectionState()) {
    _listenForActions();
    _loadSaved();
  }

  /// The underlying WebSocket client (for message streaming in other widgets).
  ClawClient get client => _client;

  /// Listen for action messages from the WebSocket and enqueue them locally.
  void _listenForActions() {
    _actionSub = _client.actions.listen((actionJson) {
      final queue = _actionQueue;
      if (queue == null) return;
      try {
        final action = ClawAction.fromJson(actionJson);
        queue.enqueue(action);
      } catch (_) {
        // Skip malformed action payloads.
      }
    });
  }

  Future<void> _loadSaved() async {
    final encoded = await _storage.read(key: StorageKeys.servers);
    final activeId = await _storage.read(key: StorageKeys.activeServerId);

    if (encoded != null) {
      final servers = ServerConfig.decodeList(encoded);
      state = state.copyWith(servers: servers, activeServerId: activeId);

      // Auto-connect to the active server on launch.
      if (state.activeServer != null) {
        await _connectToServer(state.activeServer!);
      }
    }
  }

  /// Add a new server and make it active. Called after successful auth.
  Future<void> addServer(ServerConfig server) async {
    // Replace if same id already exists (re-pairing).
    final updated = [...state.servers.where((s) => s.id != server.id), server];
    state = state.copyWith(servers: updated, activeServerId: server.id);
    await _persist();
    await _connectToServer(server);
  }

  /// Switch to a different paired server.
  Future<void> switchServer(String serverId) async {
    final server = state.servers.where((s) => s.id == serverId).firstOrNull;
    if (server == null) return;

    await _client.disconnect();
    state = state.copyWith(
      activeServerId: serverId,
      status: ConnectionStatus.disconnected,
      clearError: true,
    );
    await _storage.write(key: StorageKeys.activeServerId, value: serverId);
    await _connectToServer(server);
  }

  /// Remove a paired server. If it was active, disconnect.
  Future<void> removeServer(String serverId) async {
    final updated = state.servers.where((s) => s.id != serverId).toList();
    final wasActive = state.activeServerId == serverId;

    if (wasActive) {
      await _client.disconnect();
      await _statusSub?.cancel();
      _statusSub = null;
    }

    state = state.copyWith(
      servers: updated,
      activeServerId: wasActive
          ? (updated.isNotEmpty ? updated.first.id : null)
          : state.activeServerId,
      clearActiveServer: wasActive && updated.isEmpty,
      status: wasActive ? ConnectionStatus.disconnected : state.status,
      clearError: wasActive,
    );
    await _persist();

    // Connect to the new active server if we had to switch.
    if (wasActive && state.activeServer != null) {
      await _connectToServer(state.activeServer!);
    }
  }

  /// Update the JWT for a specific server (e.g. after token refresh).
  Future<void> updateToken(String serverId, String jwtToken,
      {String? refreshToken}) async {
    final updated = state.servers.map((s) {
      if (s.id == serverId) {
        return s.copyWith(
          jwtToken: jwtToken,
          refreshToken: refreshToken ?? s.refreshToken,
        );
      }
      return s;
    }).toList();
    state = state.copyWith(servers: updated);
    await _persist();
  }

  /// Disconnect from all servers and clear storage.
  Future<void> unpairAll() async {
    await _client.disconnect();
    await _statusSub?.cancel();
    _statusSub = null;
    await _storage.delete(key: StorageKeys.servers);
    await _storage.delete(key: StorageKeys.activeServerId);
    state = const ConnectionState();
  }

  /// Manually trigger a reconnect to the active server.
  Future<void> reconnect() async {
    final server = state.activeServer;
    if (server == null) return;
    await _client.disconnect();
    state = state.copyWith(
        status: ConnectionStatus.disconnected, clearError: true);
    await _connectToServer(server);
  }

  Future<void> _connectToServer(ServerConfig server) async {
    await _statusSub?.cancel();

    state = state.copyWith(
        status: ConnectionStatus.connecting, clearError: true);

    _statusSub = _client.statusStream.listen((wsStatus) {
      final uiStatus = switch (wsStatus) {
        ClawConnectionStatus.disconnected => ConnectionStatus.disconnected,
        ClawConnectionStatus.connecting => ConnectionStatus.connecting,
        ClawConnectionStatus.connected => ConnectionStatus.connected,
        ClawConnectionStatus.error => ConnectionStatus.error,
      };
      if (mounted) {
        state = state.copyWith(status: uiStatus);
      }
    });

    await _client.connect(
      serverUrl: server.url,
      jwtToken: server.jwtToken,
    );
  }

  Future<void> _persist() async {
    await _storage.write(
      key: StorageKeys.servers,
      value: ServerConfig.encodeList(state.servers),
    );
    if (state.activeServerId != null) {
      await _storage.write(
        key: StorageKeys.activeServerId,
        value: state.activeServerId!,
      );
    }
  }

  @override
  void dispose() {
    _actionSub?.cancel();
    _statusSub?.cancel();
    _client.dispose();
    super.dispose();
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionState>(
  (ref) {
    // Wire WebSocket actions into the local SQLite queue.
    ActionQueueService? actionQueue;
    try {
      actionQueue = ref.watch(actionQueueServiceProvider);
    } catch (_) {
      actionQueue = null;
    }
    return ConnectionNotifier(actionQueue: actionQueue);
  },
);
