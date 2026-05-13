import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/queued_action.dart';

/// HTTP client for the nself-claw server-side agent queue.
///
/// Used by the companion app to drain pending actions on (re)connect and to
/// acknowledge completion after each action executes.
///
/// Endpoints (all relative to [serverUrl]):
///   GET  `/claw/queue/drain?namespace={ns}`   — fetch + mark dispatched
///   POST `/claw/queue/ack/:action_id`          — mark completed with result
///
/// T-0950
class AgentQueueApiClient {
  final http.Client _http;

  AgentQueueApiClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  /// Drain pending actions for [namespace] from the server queue.
  ///
  /// Returns the list of actions that were waiting. The server marks all
  /// returned actions as `dispatched` atomically. Actions that are already
  /// expired are excluded automatically.
  Future<List<QueuedAction>> drainQueue({
    required String serverUrl,
    required String namespace,
    String? jwtToken,
  }) async {
    final uri = Uri.parse('$serverUrl/claw/queue/drain').replace(
      queryParameters: {'namespace': namespace},
    );

    final response = await _http.get(uri, headers: _headers(jwtToken));

    if (response.statusCode != 200) {
      throw AgentQueueException(
        'drain failed: HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final rawList = body['actions'] as List<dynamic>? ?? const [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(QueuedAction.fromJson)
        .toList();
  }

  /// Acknowledge that [actionId] has been executed.
  ///
  /// [result] is an optional payload from the execution (e.g. file contents,
  /// error description). Pass `null` if there is nothing to report.
  Future<void> acknowledgeAction({
    required String serverUrl,
    required String actionId,
    Map<String, dynamic>? result,
    String? jwtToken,
  }) async {
    final uri = Uri.parse('$serverUrl/claw/queue/ack/$actionId');
    final body = result != null ? jsonEncode({'result': result}) : '{}';

    final response = await _http.post(
      uri,
      headers: _headers(jwtToken)..['Content-Type'] = 'application/json',
      body: body,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw AgentQueueException(
        'ack failed: HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  Map<String, String> _headers(String? jwtToken) {
    final headers = <String, String>{};
    if (jwtToken != null && jwtToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $jwtToken';
    }
    return headers;
  }
}

/// Exception thrown when an agent queue HTTP call fails.
class AgentQueueException implements Exception {
  final String message;
  final int? statusCode;

  const AgentQueueException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
