// T-1173: ApiKeyProvider — API key management + usage stats for the
// OpenAI-compatible gateway at /claw/v1/api-keys and /claw/v1/usage.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'connection_provider.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class ApiKeyRecord {
  final String id;
  final String name;
  final String keyPrefix;
  final bool isActive;
  final bool adminAllowed;
  final int rpmLimit;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  const ApiKeyRecord({
    required this.id,
    required this.name,
    required this.keyPrefix,
    required this.isActive,
    required this.adminAllowed,
    required this.rpmLimit,
    required this.createdAt,
    this.lastUsedAt,
  });

  factory ApiKeyRecord.fromJson(Map<String, dynamic> json) => ApiKeyRecord(
        id: json['id'] as String,
        name: json['name'] as String,
        keyPrefix: json['key_prefix'] as String,
        isActive: json['is_active'] as bool? ?? true,
        adminAllowed: json['admin_allowed'] as bool? ?? false,
        rpmLimit: (json['rpm_limit'] as num?)?.toInt() ?? 60,
        createdAt: DateTime.parse(json['created_at'] as String),
        lastUsedAt: json['last_used_at'] != null
            ? DateTime.parse(json['last_used_at'] as String)
            : null,
      );
}

class CreatedApiKey {
  final ApiKeyRecord record;
  final String fullKey; // show once only

  const CreatedApiKey({required this.record, required this.fullKey});

  factory CreatedApiKey.fromJson(Map<String, dynamic> json) => CreatedApiKey(
        record: ApiKeyRecord.fromJson(json),
        fullKey: json['key'] as String,
      );
}

class SystemPromptRecord {
  final String id;
  final String name;
  final String content;
  final bool isDefault;
  final DateTime createdAt;

  const SystemPromptRecord({
    required this.id,
    required this.name,
    required this.content,
    required this.isDefault,
    required this.createdAt,
  });

  factory SystemPromptRecord.fromJson(Map<String, dynamic> json) =>
      SystemPromptRecord(
        id: json['id'] as String,
        name: json['name'] as String,
        content: json['content'] as String,
        isDefault: json['is_default'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class UsageRow {
  final String keyId;
  final String day;
  final String model;
  final int promptTokens;
  final int completionTokens;
  final double costUsd;

  const UsageRow({
    required this.keyId,
    required this.day,
    required this.model,
    required this.promptTokens,
    required this.completionTokens,
    required this.costUsd,
  });

  int get totalTokens => promptTokens + completionTokens;

  factory UsageRow.fromJson(Map<String, dynamic> json) => UsageRow(
        keyId: json['key_id'] as String,
        day: json['day'] as String,
        model: json['model'] as String,
        promptTokens: (json['prompt_tokens'] as num?)?.toInt() ?? 0,
        completionTokens: (json['completion_tokens'] as num?)?.toInt() ?? 0,
        costUsd: (json['cost_usd'] as num?)?.toDouble() ?? 0.0,
      );
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class ApiKeyState {
  final List<ApiKeyRecord> keys;
  final List<SystemPromptRecord> systemPrompts;
  final List<UsageRow> usage;
  final bool loading;
  final String? error;

  const ApiKeyState({
    this.keys = const [],
    this.systemPrompts = const [],
    this.usage = const [],
    this.loading = false,
    this.error,
  });

  ApiKeyState copyWith({
    List<ApiKeyRecord>? keys,
    List<SystemPromptRecord>? systemPrompts,
    List<UsageRow>? usage,
    bool? loading,
    String? error,
  }) =>
      ApiKeyState(
        keys: keys ?? this.keys,
        systemPrompts: systemPrompts ?? this.systemPrompts,
        usage: usage ?? this.usage,
        loading: loading ?? this.loading,
        error: error,
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class ApiKeyNotifier extends StateNotifier<ApiKeyState> {
  final Ref _ref;

  ApiKeyNotifier(this._ref) : super(const ApiKeyState());

  String get _base {
    final cfg = _ref.read(connectionProvider).activeServer;
    return cfg?.url ?? '';
  }

  Future<void> loadAll() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final keysResp = await http.get(Uri.parse('$_base/claw/v1/api-keys'));
      final promptsResp = await http.get(Uri.parse('$_base/claw/v1/system-prompts'));
      final usageResp = await http.get(Uri.parse('$_base/claw/v1/usage'));

      final keys = (jsonDecode(keysResp.body)['keys'] as List?)
              ?.map((e) => ApiKeyRecord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      final prompts = (jsonDecode(promptsResp.body)['prompts'] as List?)
              ?.map((e) => SystemPromptRecord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      final usage = (jsonDecode(usageResp.body)['usage'] as List?)
              ?.map((e) => UsageRow.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];

      state = state.copyWith(keys: keys, systemPrompts: prompts, usage: usage, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// Create a new API key. Returns full key (show once) or null on error.
  Future<CreatedApiKey?> createKey({
    required String name,
    bool adminAllowed = false,
    int rpmLimit = 60,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('$_base/claw/v1/api-keys'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'admin_allowed': adminAllowed,
          'rpm_limit': rpmLimit,
        }),
      );
      if (resp.statusCode == 201) {
        final created = CreatedApiKey.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>,
        );
        await loadAll();
        return created;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> revokeKey(String id) async {
    try {
      final resp = await http.delete(Uri.parse('$_base/claw/v1/api-keys/$id'));
      if (resp.statusCode == 200) {
        await loadAll();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> createSystemPrompt({
    required String name,
    required String content,
    bool isDefault = false,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('$_base/claw/v1/system-prompts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'content': content, 'is_default': isDefault}),
      );
      if (resp.statusCode == 201) {
        await loadAll();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> deleteSystemPrompt(String id) async {
    try {
      final resp = await http.delete(Uri.parse('$_base/claw/v1/system-prompts/$id'));
      if (resp.statusCode == 200) {
        await loadAll();
        return true;
      }
    } catch (_) {}
    return false;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final apiKeyProvider = StateNotifierProvider<ApiKeyNotifier, ApiKeyState>((ref) {
  return ApiKeyNotifier(ref);
});
