import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _storageKey = 'nclaw_wizard_state';
const _storage = FlutterSecureStorage();

/// IDs for plugins shown on Screen 3.
const kPluginGoogle = 'google';
const kPluginNotify = 'notify';
const kPluginBrowser = 'browser';
const kPluginVoice = 'voice';
const kPluginCron = 'cron';

const kAllWizardPlugins = [
  kPluginGoogle,
  kPluginNotify,
  kPluginBrowser,
  kPluginVoice,
  kPluginCron,
];

/// Agent template identifiers.
const kTemplatePersonalAssistant = 'personal_assistant';
const kTemplateResearchAgent = 'research_agent';
const kTemplateWritingCoach = 'writing_coach';
const kTemplateCodeReviewer = 'code_reviewer';
const kTemplateCustom = 'custom';

// ---------------------------------------------------------------------------
// Schedule model
// ---------------------------------------------------------------------------

/// Schedule preferences captured on Screen 4.
class WizardSchedule {
  final String timezone;
  final String wakeTime; // HH:mm (24h)
  final bool morningBriefing;
  final bool eodSummary;
  final bool weeklyReview;

  const WizardSchedule({
    this.timezone = 'America/New_York',
    this.wakeTime = '07:30',
    this.morningBriefing = true,
    this.eodSummary = true,
    this.weeklyReview = false,
  });

  WizardSchedule copyWith({
    String? timezone,
    String? wakeTime,
    bool? morningBriefing,
    bool? eodSummary,
    bool? weeklyReview,
  }) {
    return WizardSchedule(
      timezone: timezone ?? this.timezone,
      wakeTime: wakeTime ?? this.wakeTime,
      morningBriefing: morningBriefing ?? this.morningBriefing,
      eodSummary: eodSummary ?? this.eodSummary,
      weeklyReview: weeklyReview ?? this.weeklyReview,
    );
  }

  Map<String, dynamic> toJson() => {
        'timezone': timezone,
        'wake_time': wakeTime,
        'morning_briefing': morningBriefing,
        'eod_summary': eodSummary,
        'weekly_review': weeklyReview,
      };

  factory WizardSchedule.fromJson(Map<String, dynamic> j) => WizardSchedule(
        timezone: j['timezone'] as String? ?? 'America/New_York',
        wakeTime: j['wake_time'] as String? ?? '07:30',
        morningBriefing: j['morning_briefing'] as bool? ?? true,
        eodSummary: j['eod_summary'] as bool? ?? true,
        weeklyReview: j['weekly_review'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// WizardState
// ---------------------------------------------------------------------------

/// Persisted state for the first-run bootstrap wizard (Screens 3–5).
///
/// Written to [FlutterSecureStorage] after every mutation so the wizard
/// can resume at the last incomplete screen if the app is restarted.
class WizardState {
  /// Which optional plugins the user enabled on Screen 3.
  final Set<String> selectedPlugins;

  /// Schedule preferences from Screen 4 (only populated if cron selected).
  final WizardSchedule? schedule;

  /// Agent template chosen on Screen 5.
  final String? agentTemplate;

  /// True once [wizard_complete.dart] has successfully called the backend.
  final bool completed;

  /// The last screen the user was on (0–5). Used for resume.
  final int lastScreen;

  const WizardState({
    this.selectedPlugins = const {},
    this.schedule,
    this.agentTemplate,
    this.completed = false,
    this.lastScreen = 3,
  });

  WizardState copyWith({
    Set<String>? selectedPlugins,
    WizardSchedule? schedule,
    String? agentTemplate,
    bool? completed,
    int? lastScreen,
  }) {
    return WizardState(
      selectedPlugins: selectedPlugins ?? this.selectedPlugins,
      schedule: schedule ?? this.schedule,
      agentTemplate: agentTemplate ?? this.agentTemplate,
      completed: completed ?? this.completed,
      lastScreen: lastScreen ?? this.lastScreen,
    );
  }

  Map<String, dynamic> toJson() => {
        'selected_plugins': selectedPlugins.toList(),
        'schedule': schedule?.toJson(),
        'agent_template': agentTemplate,
        'completed': completed,
        'last_screen': lastScreen,
      };

  factory WizardState.fromJson(Map<String, dynamic> j) => WizardState(
        selectedPlugins: Set<String>.from(
          (j['selected_plugins'] as List<dynamic>?)?.cast<String>() ?? [],
        ),
        schedule: j['schedule'] != null
            ? WizardSchedule.fromJson(
                Map<String, dynamic>.from(j['schedule'] as Map))
            : null,
        agentTemplate: j['agent_template'] as String?,
        completed: j['completed'] as bool? ?? false,
        lastScreen: j['last_screen'] as int? ?? 3,
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class WizardStateNotifier extends StateNotifier<WizardState> {
  WizardStateNotifier() : super(const WizardState()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null) {
        state = WizardState.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Fresh install or corrupt — start from defaults.
    }
  }

  Future<void> _persist() async {
    await _storage.write(key: _storageKey, value: jsonEncode(state.toJson()));
  }

  /// Toggle a plugin on/off.
  Future<void> togglePlugin(String pluginId, {required bool enabled}) async {
    final updated = Set<String>.from(state.selectedPlugins);
    if (enabled) {
      updated.add(pluginId);
    } else {
      updated.remove(pluginId);
    }
    state = state.copyWith(selectedPlugins: updated);
    await _persist();
  }

  /// Update schedule preferences.
  Future<void> setSchedule(WizardSchedule schedule) async {
    state = state.copyWith(schedule: schedule);
    await _persist();
  }

  /// Set the chosen agent template.
  Future<void> setTemplate(String templateId) async {
    state = state.copyWith(agentTemplate: templateId);
    await _persist();
  }

  /// Advance the last-seen screen pointer.
  Future<void> advanceTo(int screen) async {
    if (screen > state.lastScreen) {
      state = state.copyWith(lastScreen: screen);
      await _persist();
    }
  }

  /// Mark wizard as fully complete. Called by [wizard_complete.dart].
  Future<void> markComplete() async {
    state = state.copyWith(completed: true);
    await _persist();
  }

  /// Reset wizard state (for testing / debug).
  Future<void> reset() async {
    state = const WizardState();
    await _storage.delete(key: _storageKey);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final wizardStateProvider =
    StateNotifierProvider<WizardStateNotifier, WizardState>(
  (ref) => WizardStateNotifier(),
);
