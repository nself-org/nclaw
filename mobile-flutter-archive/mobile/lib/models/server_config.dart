import 'dart:convert';

/// Configuration for a paired nSelf server running the nself-claw plugin.
class ServerConfig {
  final String id;
  final String url;
  final String name;
  final String? jwtToken;
  final String? refreshToken;

  const ServerConfig({
    required this.id,
    required this.url,
    required this.name,
    this.jwtToken,
    this.refreshToken,
  });

  ServerConfig copyWith({
    String? url,
    String? name,
    String? jwtToken,
    String? refreshToken,
  }) {
    return ServerConfig(
      id: id,
      url: url ?? this.url,
      name: name ?? this.name,
      jwtToken: jwtToken ?? this.jwtToken,
      refreshToken: refreshToken ?? this.refreshToken,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'name': name,
        'jwtToken': jwtToken,
        'refreshToken': refreshToken,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        id: json['id'] as String,
        url: json['url'] as String,
        name: json['name'] as String,
        jwtToken: json['jwtToken'] as String?,
        refreshToken: json['refreshToken'] as String?,
      );

  /// Encode a list of server configs to a JSON string for secure storage.
  static String encodeList(List<ServerConfig> servers) =>
      jsonEncode(servers.map((s) => s.toJson()).toList());

  /// Decode a JSON string from secure storage into a list of server configs.
  static List<ServerConfig> decodeList(String encoded) {
    final list = jsonDecode(encoded) as List<dynamic>;
    return list
        .map((e) => ServerConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ServerConfig && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
