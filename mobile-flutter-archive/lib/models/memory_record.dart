/// Memory record model for the memory explorer (E-26-03).
///
/// Shared across facts, decisions, entities, and timeline views.
class MemoryRecord {
  final String id;
  final String entityId;
  final String entityType; // 'fact', 'decision', 'entity', 'event'
  final String content;
  final double confidence;
  final int timesReinforced;
  final String source;
  final String? status; // for decisions: 'active', 'superseded', 'rejected'
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const MemoryRecord({
    required this.id,
    required this.entityId,
    required this.entityType,
    required this.content,
    this.confidence = 1.0,
    this.timesReinforced = 1,
    this.source = '',
    this.status,
    this.metadata,
    required this.createdAt,
    this.updatedAt,
  });

  factory MemoryRecord.fromJson(Map<String, dynamic> json) => MemoryRecord(
        id: json['id'] as String? ?? '',
        entityId: json['entity_id'] as String? ?? '',
        entityType: json['entity_type'] as String? ?? 'fact',
        content: json['content'] as String? ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
        timesReinforced: (json['times_reinforced'] as num?)?.toInt() ?? 1,
        source: json['source'] as String? ?? '',
        status: json['status'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'] as String)
            : null,
      );
}
