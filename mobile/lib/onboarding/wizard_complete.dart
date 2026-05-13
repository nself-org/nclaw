import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../providers/connection_provider.dart';
import 'wizard_state.dart';

// ---------------------------------------------------------------------------
// Completion result
// ---------------------------------------------------------------------------

class WizardCompleteResult {
  final bool success;
  final String? agentId;
  final List<String> installedPlugins;
  final List<String> enabledRecipes;
  final String? error;

  const WizardCompleteResult({
    required this.success,
    this.agentId,
    this.installedPlugins = const [],
    this.enabledRecipes = const [],
    this.error,
  });

  factory WizardCompleteResult.failure(String error) =>
      WizardCompleteResult(success: false, error: error);
}

// ---------------------------------------------------------------------------
// Commit action
// ---------------------------------------------------------------------------

/// Sends the full [WizardState] payload to [POST /claw/onboarding/complete].
///
/// The backend creates the agent, installs selected plugins, and enables
/// chosen recipes in a single transaction. The endpoint is idempotent —
/// repeated calls are safe (ON CONFLICT DO UPDATE on the user's row).
///
/// Returns a [WizardCompleteResult] that the calling widget can inspect.
/// On success the notifier's [markComplete()] is called so the wizard never
/// shows again on next launch.
Future<WizardCompleteResult> commitWizard(
  WidgetRef ref, {
  /// Override base URL for testing.
  String? baseUrlOverride,
}) async {
  final wizard = ref.read(wizardStateProvider);
  final notifier = ref.read(wizardStateProvider.notifier);
  final connection = ref.read(connectionProvider);
  final baseUrl =
      baseUrlOverride ?? connection.activeServer?.url ?? '';

  if (baseUrl.isEmpty) {
    return WizardCompleteResult.failure('No server configured.');
  }

  final payload = _buildPayload(wizard);

  try {
    final uri = Uri.parse('$baseUrl/claw/onboarding/complete');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await notifier.markComplete();
      return WizardCompleteResult(
        success: true,
        agentId: data['agent_id'] as String?,
        installedPlugins: _asList(data['installed_plugins']),
        enabledRecipes: _asList(data['enabled_recipes']),
      );
    } else {
      final body = _safeBody(response.body);
      return WizardCompleteResult.failure(
        'Server returned ${response.statusCode}: ${body['error'] ?? 'unknown'}',
      );
    }
  } on Exception catch (e) {
    return WizardCompleteResult.failure('Network error: $e');
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds the JSON payload from the current wizard state.
///
/// POST /claw/onboarding/complete
/// Body: { plugins, schedule, template }
Map<String, dynamic> _buildPayload(WizardState wizard) {
  final Map<String, dynamic> payload = {
    'plugins': wizard.selectedPlugins.toList(),
    'template': wizard.agentTemplate ?? kTemplatePersonalAssistant,
  };
  if (wizard.selectedPlugins.contains(kPluginCron) &&
      wizard.schedule != null) {
    payload['schedule'] = wizard.schedule!.toJson();
  }
  return payload;
}

List<String> _asList(dynamic raw) {
  if (raw is List) return raw.cast<String>();
  return [];
}

Map<String, dynamic> _safeBody(String raw) {
  try {
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}
