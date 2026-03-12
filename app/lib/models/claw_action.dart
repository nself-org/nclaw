import 'dart:convert';

/// Action types that the nself-claw backend can request from the companion app.
enum ActionType {
  fileOp,
  oauth,
  shell,
  browser,
  notification;

  /// Serialize to a string for storage and JSON.
  String toJson() => name;

  /// Deserialize from a string.
  static ActionType fromJson(String value) {
    return ActionType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ActionType.notification,
    );
  }
}

/// Lifecycle status of an action in the queue.
enum ActionStatus {
  pending,
  approved,
  executing,
  done,
  failed,
  expired;

  String toJson() => name;

  static ActionStatus fromJson(String value) {
    return ActionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ActionStatus.pending,
    );
  }
}

/// A single action received from the nself-claw backend.
///
/// Actions flow through the queue: pending -> approved -> executing -> done/failed.
/// Expired actions are those older than 24 hours that were never approved.
class ClawAction {
  final String id;
  final String sessionId;
  final ActionType type;
  final Map<String, dynamic> params;
  final ActionStatus status;
  final Map<String, dynamic>? result;
  final DateTime createdAt;
  final DateTime? executedAt;
  final DateTime expiresAt;

  const ClawAction({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.params,
    required this.status,
    this.result,
    required this.createdAt,
    this.executedAt,
    required this.expiresAt,
  });

  /// Whether this action can still be approved (not expired, not already processed).
  bool get isPending => status == ActionStatus.pending && !isExpired;

  /// Whether the action has passed its expiration time.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Whether the action is in a terminal state.
  bool get isTerminal =>
      status == ActionStatus.done ||
      status == ActionStatus.failed ||
      status == ActionStatus.expired;

  ClawAction copyWith({
    ActionStatus? status,
    Map<String, dynamic>? result,
    DateTime? executedAt,
  }) {
    return ClawAction(
      id: id,
      sessionId: sessionId,
      type: type,
      params: params,
      status: status ?? this.status,
      result: result ?? this.result,
      createdAt: createdAt,
      executedAt: executedAt ?? this.executedAt,
      expiresAt: expiresAt,
    );
  }

  /// Serialize to a map for SQLite storage.
  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'type': type.toJson(),
        'params': jsonEncode(params),
        'status': status.toJson(),
        'result': result != null ? jsonEncode(result!) : null,
        'created_at': createdAt.toIso8601String(),
        'executed_at': executedAt?.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
      };

  /// Deserialize from a SQLite row map.
  factory ClawAction.fromMap(Map<String, dynamic> map) {
    return ClawAction(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      type: ActionType.fromJson(map['type'] as String),
      params: jsonDecode(map['params'] as String) as Map<String, dynamic>,
      status: ActionStatus.fromJson(map['status'] as String),
      result: map['result'] != null
          ? jsonDecode(map['result'] as String) as Map<String, dynamic>
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      executedAt: map['executed_at'] != null
          ? DateTime.parse(map['executed_at'] as String)
          : null,
      expiresAt: DateTime.parse(map['expires_at'] as String),
    );
  }

  /// Deserialize from a WebSocket JSON message payload.
  factory ClawAction.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ClawAction(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String? ?? '',
      type: ActionType.fromJson(json['type'] as String? ?? 'notification'),
      params: (json['params'] as Map<String, dynamic>?) ?? const {},
      status: ActionStatus.fromJson(json['status'] as String? ?? 'pending'),
      result: json['result'] as Map<String, dynamic>?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : now,
      executedAt: json['executedAt'] != null
          ? DateTime.parse(json['executedAt'] as String)
          : null,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : now.add(const Duration(hours: 24)),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ClawAction && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
