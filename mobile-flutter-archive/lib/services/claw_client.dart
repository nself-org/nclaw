import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Connection status for the WebSocket client.
enum ClawConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// WebSocket client for connecting to a self-hosted nself-claw backend.
///
/// The nself-claw plugin runs on port 3710 by default and exposes a WebSocket
/// endpoint at `/ws` for real-time communication with companion apps.
///
/// Features:
/// - JWT authentication via query parameter
/// - Ping/pong heartbeat every 30 seconds
/// - Auto-reconnect with exponential backoff (max 60s)
class ClawClient {
  WebSocketChannel? _channel;
  ClawConnectionStatus _status = ClawConnectionStatus.disconnected;
  StreamSubscription<dynamic>? _subscription;

  // Reconnection state.
  String? _lastServerUrl;
  String? _lastJwtToken;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _shouldReconnect = false;
  static const _maxBackoffSeconds = 60;
  static const _baseBackoffMs = 500;

  // Heartbeat state.
  Timer? _heartbeatTimer;
  static const _heartbeatInterval = Duration(seconds: 30);

  /// Current connection status.
  ClawConnectionStatus get status => _status;

  /// Stream controller for incoming messages from the backend.
  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of parsed JSON messages from the nself-claw backend.
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// Stream controller for connection status changes.
  final _statusController =
      StreamController<ClawConnectionStatus>.broadcast();

  /// Stream of connection status updates.
  Stream<ClawConnectionStatus> get statusStream => _statusController.stream;

  /// Connect to the nself-claw backend WebSocket endpoint.
  ///
  /// [serverUrl] should be the base URL of the nself server, e.g.
  /// `https://my-server.example.com`. The client will connect to the
  /// nself-claw WebSocket at the standard path.
  ///
  /// [jwtToken] is the Hasura Auth JWT for the user session.
  Future<void> connect({
    required String serverUrl,
    String? jwtToken,
  }) async {
    if (_status == ClawConnectionStatus.connecting ||
        _status == ClawConnectionStatus.connected) {
      return;
    }

    _lastServerUrl = serverUrl;
    _lastJwtToken = jwtToken;
    _shouldReconnect = true;
    _reconnectAttempts = 0;

    await _doConnect(serverUrl, jwtToken);
  }

  /// Disconnect from the backend. Stops auto-reconnect.
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();

    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _setStatus(ClawConnectionStatus.disconnected);
  }

  /// Send a JSON message to the backend.
  void send(Map<String, dynamic> message) {
    if (_status != ClawConnectionStatus.connected || _channel == null) {
      return;
    }
    _channel!.sink.add(jsonEncode(message));
  }

  /// Clean up all resources.
  Future<void> dispose() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    await disconnect();
    await _actionController.close();
    await _messageController.close();
    await _statusController.close();
  }

  // -- Internal --

  Future<void> _doConnect(String serverUrl, String? jwtToken) async {
    _setStatus(ClawConnectionStatus.connecting);

    try {
      final wsUrl = _buildWsUrl(serverUrl, jwtToken);

      _channel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
        protocols: ['nclaw-v1'],
      );

      await _channel!.ready;
      _setStatus(ClawConnectionStatus.connected);
      _reconnectAttempts = 0;
      _startHeartbeat();

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      _setStatus(ClawConnectionStatus.error);
      _scheduleReconnect();
    }
  }

  /// Build the WebSocket URL with JWT passed as a query parameter.
  /// Query param auth is required because the web_socket_channel package
  /// does not support custom headers on all platforms (especially web).
  String _buildWsUrl(String serverUrl, String? jwtToken) {
    final uri = Uri.parse(serverUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final queryParams = <String, String>{};
    if (jwtToken != null) {
      queryParams['token'] = jwtToken;
    }
    final query =
        queryParams.isNotEmpty ? '?${Uri(queryParameters: queryParams).query}' : '';
    return '$scheme://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/claw/ws$query';
  }

  /// Stream controller for action messages specifically.
  final _actionController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of action payloads received from the backend.
  /// Each map is the `action` field from `{"type":"action","action":{...}}`.
  Stream<Map<String, dynamic>> get actions => _actionController.stream;

  void _onMessage(dynamic data) {
    try {
      final decoded = jsonDecode(data as String) as Map<String, dynamic>;

      // Handle pong responses from the server (heartbeat ack).
      if (decoded['type'] == 'pong') return;

      // Route action messages to the dedicated action stream.
      if (decoded['type'] == 'action' && decoded['action'] is Map) {
        _actionController
            .add(decoded['action'] as Map<String, dynamic>);
      }

      // Route action status updates (server confirms execution result).
      if (decoded['type'] == 'action_update' && decoded['action'] is Map) {
        _actionController
            .add(decoded['action'] as Map<String, dynamic>);
      }

      _messageController.add(decoded);
    } catch (_) {
      // Skip malformed messages.
    }
  }

  void _onError(Object error) {
    _setStatus(ClawConnectionStatus.error);
    _stopHeartbeat();
    _scheduleReconnect();
  }

  void _onDone() {
    _stopHeartbeat();
    _setStatus(ClawConnectionStatus.disconnected);
    _scheduleReconnect();
  }

  void _setStatus(ClawConnectionStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  // -- Heartbeat --

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      send({'type': 'ping'});
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // -- Auto-reconnect with exponential backoff --

  void _scheduleReconnect() {
    if (!_shouldReconnect || _lastServerUrl == null) return;

    _reconnectTimer?.cancel();

    // Exponential backoff: 500ms, 1s, 2s, 4s, ... capped at 60s.
    final delayMs = min(
      _baseBackoffMs * pow(2, _reconnectAttempts).toInt(),
      _maxBackoffSeconds * 1000,
    );
    _reconnectAttempts++;

    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_shouldReconnect && _lastServerUrl != null) {
        _doConnect(_lastServerUrl!, _lastJwtToken);
      }
    });
  }
}
