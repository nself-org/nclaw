import 'dart:convert';

/// An action dispatched from the nself-claw plugin into the server-side
/// agent queue, waiting to be delivered to this companion app.
///
/// The server stores these in `np_claw_agent_queue`. The companion drains them
/// on every (re)connect via GET /claw/queue/drain, executes each one, and
/// acknowledges completion via POST /claw/queue/ack/:id.
///
/// T-0950
class QueuedAction {
  final String id;
  final String namespace;
  final String action;
  final Map<String, dynamic> payload;
  final String? idempotencyKey;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;

  const QueuedAction({
    required this.id,
    required this.namespace,
    required this.action,
    required this.payload,
    this.idempotencyKey,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Whether the action is still within its TTL window.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  factory QueuedAction.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return QueuedAction(
      id: json['id'] as String,
      namespace: json['namespace'] as String? ?? '',
      action: json['action'] as String? ?? '',
      payload: _parsePayload(json['payload']),
      idempotencyKey: json['idempotency_key'] as String?,
      status: json['status'] as String? ?? 'pending',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : now,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : now.add(const Duration(hours: 24)),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'namespace': namespace,
        'action': action,
        'payload': payload,
        'idempotency_key': idempotencyKey,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      };

  static Map<String, dynamic> _parsePayload(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return const {};
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is QueuedAction && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
