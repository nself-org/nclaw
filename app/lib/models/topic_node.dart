/// Topic tree node for the sidebar drawer (E-26-01).
///
/// Mirrors the web TopicNode spec: infinite nesting via ltree paths,
/// color/icon customization, unread badge counts.
class TopicNode {
  final String id;
  final String name;
  final String? parentId;
  final String path; // ltree path e.g. "root.work.project_a"
  final int depth;
  final String? color; // hex color e.g. "#0EA5E9"
  final String? icon; // material icon name or emoji
  final int unreadCount;
  final int messageCount;
  final int sortOrder;
  final bool isExpanded;
  final DateTime createdAt;
  final DateTime? lastMessageAt;
  final List<TopicNode> children;

  const TopicNode({
    required this.id,
    required this.name,
    this.parentId,
    required this.path,
    this.depth = 0,
    this.color,
    this.icon,
    this.unreadCount = 0,
    this.messageCount = 0,
    this.sortOrder = 0,
    this.isExpanded = false,
    required this.createdAt,
    this.lastMessageAt,
    this.children = const [],
  });

  factory TopicNode.fromJson(Map<String, dynamic> json) => TopicNode(
        id: json['id'] as String,
        name: json['name'] as String,
        parentId: json['parent_id'] as String?,
        path: json['path'] as String? ?? '',
        depth: (json['depth'] as num?)?.toInt() ?? 0,
        color: json['color'] as String?,
        icon: json['icon'] as String?,
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
        messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        isExpanded: json['is_expanded'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
        lastMessageAt: json['last_message_at'] != null
            ? DateTime.tryParse(json['last_message_at'] as String)
            : null,
        children: (json['children'] as List<dynamic>?)
                ?.map((c) => TopicNode.fromJson(c as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  TopicNode copyWith({
    String? name,
    String? color,
    String? icon,
    int? unreadCount,
    int? sortOrder,
    bool? isExpanded,
    List<TopicNode>? children,
  }) =>
      TopicNode(
        id: id,
        name: name ?? this.name,
        parentId: parentId,
        path: path,
        depth: depth,
        color: color ?? this.color,
        icon: icon ?? this.icon,
        unreadCount: unreadCount ?? this.unreadCount,
        messageCount: messageCount,
        sortOrder: sortOrder ?? this.sortOrder,
        isExpanded: isExpanded ?? this.isExpanded,
        createdAt: createdAt,
        lastMessageAt: lastMessageAt,
        children: children ?? this.children,
      );
}
