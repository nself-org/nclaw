// intelligence_service.dart — Flutter gRPC client for the nclaw intelligence service.
//
// Purpose: Provide a typed Dart client wrapping the nclaw-intelligence gRPC server
//          (port NCLAW_INTELLIGENCE_PORT, default 9441 per F10-PORT-REGISTRY.md).
//          Exposes searchMemory, insertMemory, queryKnowledge, and invokeTool as
//          async methods returning domain result types. Host and port come from
//          constructor parameters — never hardcoded.
// Inputs:  host (String), port (int) — injected at construction time via DI.
// Outputs: List<MemoryResult>, void, List<KnowledgeResult>, AgentToolResult.
// Constraints: No hardcoded host, port, or IP addresses. ≤150 lines.
//              Auth stub: NCLAW_DEV_BYPASS_AUTH mode; TODO(E2) wires JWT interceptor.
// SPORT: nclaw-memory-architecture-spec.md §7 §9 — P2-E5-W4-S8-T08.

import 'dart:convert';
import 'package:http/http.dart' as http;

// ─── Domain result types ──────────────────────────────────────────────────────

/// A single memory record returned by [IntelligenceService.searchMemory].
class MemoryResult {
  /// UUID of the nclaw_user_memories row.
  final String id;

  /// Raw text content of the memory.
  final String content;

  /// Classification: "fact" | "preference" | "decision" | "audit".
  final String memoryType;

  /// Scoped namespace (e.g. "personal/nclaw_{userID}").
  final String namespace;

  /// RFC3339 timestamp when the memory was first stored.
  final String validFrom;

  /// RFC3339 expiry timestamp; empty string means the record is active.
  final String validUntil;

  /// RRF-reranked relevance score (higher = more relevant).
  final double score;

  const MemoryResult({
    required this.id,
    required this.content,
    required this.memoryType,
    required this.namespace,
    required this.validFrom,
    required this.validUntil,
    required this.score,
  });

  factory MemoryResult.fromJson(Map<String, dynamic> json) => MemoryResult(
        id: json['id'] as String? ?? '',
        content: json['content'] as String? ?? '',
        memoryType: json['memory_type'] as String? ?? 'fact',
        namespace: json['namespace'] as String? ?? '',
        validFrom: json['valid_from'] as String? ?? '',
        validUntil: json['valid_until'] as String? ?? '',
        score: (json['score'] as num?)?.toDouble() ?? 0.0,
      );
}

/// A single knowledge chunk returned by [IntelligenceService.queryKnowledge].
class KnowledgeResult {
  /// UUID of the nclaw_org_knowledge row.
  final String id;

  /// Raw chunk text.
  final String content;

  /// Document classification (e.g. "runbook", "wiki").
  final String docType;

  /// Original document URI or key.
  final String sourceRef;

  /// Org namespace this chunk belongs to.
  final String orgSlug;

  /// RRF-reranked relevance score (higher = more relevant).
  final double score;

  const KnowledgeResult({
    required this.id,
    required this.content,
    required this.docType,
    required this.sourceRef,
    required this.orgSlug,
    required this.score,
  });

  factory KnowledgeResult.fromJson(Map<String, dynamic> json) => KnowledgeResult(
        id: json['id'] as String? ?? '',
        content: json['content'] as String? ?? '',
        docType: json['doc_type'] as String? ?? '',
        sourceRef: json['source_ref'] as String? ?? '',
        orgSlug: json['org_slug'] as String? ?? '',
        score: (json['score'] as num?)?.toDouble() ?? 0.0,
      );
}

/// The result of an agent tool invocation.
class AgentToolResult {
  /// JSON-encoded result from the tool on success; empty string on error.
  final String resultJson;

  /// Human-readable error message on failure; empty string on success.
  final String error;

  /// Name of the tool that was invoked.
  final String toolName;

  const AgentToolResult({
    required this.resultJson,
    required this.error,
    required this.toolName,
  });

  /// Whether the invocation succeeded (no error).
  bool get isSuccess => error.isEmpty;
}

// ─── IntelligenceService ──────────────────────────────────────────────────────

/// gRPC client for the nclaw intelligence service.
///
/// Connects to the nclaw-intelligence server at [_host]:[_port]
/// (default port 9441 per F10-PORT-REGISTRY.md). Host and port are injected
/// via the constructor — never hardcoded in this class.
///
/// NOTE: In P2 the server speaks a JSON-over-HTTP/1.1 facade while the full
/// gRPC HTTP/2 + protobuf wire protocol is being finalised. The grpc package
/// import is in pubspec.yaml; the call pattern will migrate to ClientChannel
/// in the next ticket once `make proto` generates Dart stubs end-to-end.
/// TODO(E5-next): replace http.Client calls with grpc.ClientChannel + generated stubs.
class IntelligenceService {
  final String _host;
  final int _port;
  final http.Client _client;

  /// Creates an [IntelligenceService] that connects to [host]:[port].
  ///
  /// [client] is optional; pass a mock for testing.
  IntelligenceService({
    required String host,
    required int port,
    http.Client? client,
  })  : _host = host,
        _port = port,
        _client = client ?? http.Client();

  String get _baseUrl => 'http://$_host:$_port';

  // ─── Memory ─────────────────────────────────────────────────────────────────

  /// Search memory facts for [userId] matching [query].
  ///
  /// Returns the top [topK] results ordered by relevance (default 5).
  Future<List<MemoryResult>> searchMemory(
    String query,
    String userId, {
    String sourceAccountId = 'primary',
    int topK = 5,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/v1/memory/search'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'query': query,
        'user_id': userId,
        'source_account_id': sourceAccountId,
        'top_k': topK,
      }),
    );
    _checkStatus(response, 'memory/search');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = body['results'] as List<dynamic>? ?? [];
    return results
        .map((r) => MemoryResult.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Insert a new memory [content] for [userId] into [namespace].
  ///
  /// [memoryType] defaults to "fact"; valid values: fact, preference, decision, audit.
  Future<void> insertMemory(
    String content,
    String userId,
    String namespace, {
    String sourceAccountId = 'primary',
    String memoryType = 'fact',
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/v1/memory/insert'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'source_account_id': sourceAccountId,
        'content': content,
        'namespace': namespace,
        'memory_type': memoryType,
      }),
    );
    _checkStatus(response, 'memory/insert');
  }

  // ─── Knowledge ───────────────────────────────────────────────────────────────

  /// Query org knowledge for [orgSlug] matching [query].
  ///
  /// Returns the top [topK] knowledge chunks ordered by relevance (default 5).
  Future<List<KnowledgeResult>> queryKnowledge(
    String query,
    String orgSlug, {
    String sourceAccountId = 'primary',
    int topK = 5,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/v1/knowledge/query'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'query': query,
        'org_slug': orgSlug,
        'source_account_id': sourceAccountId,
        'top_k': topK,
      }),
    );
    _checkStatus(response, 'knowledge/query');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = body['results'] as List<dynamic>? ?? [];
    return results
        .map((r) => KnowledgeResult.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // ─── Agent tools ─────────────────────────────────────────────────────────────

  /// Invoke a named nSelf backend agent tool with [params].
  ///
  /// [confirmed] is required for Tier 2 write tools.
  /// [authorizeToken] is required for Tier 3 destructive tools.
  Future<AgentToolResult> invokeTool(
    String toolName,
    Map<String, dynamic> params, {
    String userId = '',
    String sourceAccountId = 'primary',
    bool confirmed = false,
    String authorizeToken = '',
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/v1/agenttools/invoke'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'tool_name': toolName,
        'params_json': jsonEncode(params),
        'user_id': userId,
        'confirmed': confirmed,
        'authorize_token': authorizeToken,
        'source_account_id': sourceAccountId,
      }),
    );
    _checkStatus(response, 'agenttools/invoke');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return AgentToolResult(
      resultJson: body['result_json'] as String? ?? '',
      error: body['error'] as String? ?? '',
      toolName: body['tool_name'] as String? ?? toolName,
    );
  }

  /// Throw [Exception] if [response] status is not 2xx.
  void _checkStatus(http.Response response, String endpoint) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'IntelligenceService: $endpoint returned ${response.statusCode}: ${response.body}',
      );
    }
  }

  /// Release resources held by the underlying HTTP client.
  void dispose() => _client.close();
}
