import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Upgrade prompt configuration from the backend
class UpgradeConfig {
  final bool upgradePromptDisabled;
  final DateTime? lastUpgradePromptAt;

  UpgradeConfig({
    required this.upgradePromptDisabled,
    this.lastUpgradePromptAt,
  });

  factory UpgradeConfig.fromJson(Map<String, dynamic> json) {
    return UpgradeConfig(
      upgradePromptDisabled: json['upgrade_prompt_disabled'] ?? false,
      lastUpgradePromptAt: json['last_upgrade_prompt_at'] != null
          ? DateTime.parse(json['last_upgrade_prompt_at'])
          : null,
    );
  }
}

/// UpgradeNudge — modal dialog when device handles current tier well above target.
/// Single-fire per session + deferral logic.
///
/// Copy: "Your device handled the T<N> benchmark well above target. Want to try T<N+1>?"
/// Buttons: "Yes, upgrade", "Not now", "Don't ask again"
///
/// T4 special case: additional opt-in confirmation (T4 is not automatic).
class UpgradeNudge extends StatefulWidget {
  final int currentTier; // 0–4
  final int recommendedTier; // next tier up
  final VoidCallback? onDismiss;

  const UpgradeNudge({
    Key? key,
    required this.currentTier,
    required this.recommendedTier,
    this.onDismiss,
  }) : super(key: key);

  @override
  State<UpgradeNudge> createState() => _UpgradeNudgeState();
}

class _UpgradeNudgeState extends State<UpgradeNudge> {
  bool _sessionShown = false;
  bool _showT4Confirmation = false;

  @override
  void initState() {
    super.initState();
    _checkShouldShow();
  }

  /// Check if upgrade prompt should be shown based on config state.
  /// Single-fire: once shown in this session, never show again.
  Future<void> _checkShouldShow() async {
    if (_sessionShown) return
    _sessionShown = true

    try {
      // TODO (S15.T17): Replace stub with actual invoke to native method
      // final configJson = await UpgradeService.getUpgradeConfig()
      // final config = UpgradeConfig.fromJson(configJson)

      // For now, assume config allows showing
      // In production, check:
      // - config.upgradePromptDisabled
      // - config.lastUpgradePromptAt (defer if < 30 days)

      if (!mounted) return
      // Prompt is shown by parent widget when ready
    } catch (e) {
      debugPrint('Failed to check upgrade config: $e')
    }
  }

  void _handleUpgrade() async {
    if (widget.recommendedTier == 4) {
      setState(() => _showT4Confirmation = true);
      return;
    }
    await _performUpgrade();
  }

  void _handleConfirmT4() async {
    await _performUpgrade();
  }

  Future<void> _performUpgrade() async {
    try {
      // TODO (S15.T17): Replace stub with actual invoke
      // await UpgradeService.upgradeToTier(widget.recommendedTier);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onDismiss?.call();
    } catch (e) {
      debugPrint('Failed to upgrade tier: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upgrade: $e')),
        );
      }
    }
  }

  void _handleNotNow() async {
    try {
      // TODO (S15.T17): Replace stub with actual invoke
      // await UpgradeService.deferUpgradePrompt30Days();
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onDismiss?.call();
    } catch (e) {
      debugPrint('Failed to defer upgrade prompt: $e');
    }
  }

  void _handleDontAskAgain() async {
    try {
      // TODO (S15.T17): Replace stub with actual invoke
      // await UpgradeService.setUpgradePromptDisabled(true);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onDismiss?.call();
    } catch (e) {
      debugPrint('Failed to disable upgrade prompt: $e');
    }
  }

  String _tierLabel(int t) => (t >= 0 && t <= 4) ? 'T$t' : 'Unknown';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _showT4Confirmation ? 'Confirm T4 Upgrade' : 'Upgrade Available',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Text(
        _showT4Confirmation
            ? 'T4 (Heavy) is opt-in only — it uses very large models that may significantly impact your device. Continue?'
            : 'Your device handled the ${_tierLabel(widget.currentTier)} benchmark well above target. Want to try ${_tierLabel(widget.recommendedTier)}? It uses more RAM and disk but produces better answers.',
      ),
      actions: _showT4Confirmation
          ? [
              TextButton(
                onPressed: () => setState(() => _showT4Confirmation = false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: _handleConfirmT4,
                child: const Text('Continue'),
              ),
            ]
          : [
              TextButton(
                onPressed: _handleDontAskAgain,
                child: const Text(
                  "Don't ask again",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: _handleNotNow,
                child: const Text('Not now'),
              ),
              TextButton(
                onPressed: _handleUpgrade,
                child: const Text('Yes, upgrade'),
              ),
            ],
    )
  }
}

/// Helper service stub for invoking native upgrade operations.
/// Replace invocations with actual platform channel calls in S15.T17.
class UpgradeService {
  static const platform = MethodChannel('com.nclaw/upgrade');

  static Future<Map<String, dynamic>> getUpgradeConfig() async {
    try {
      final Map<dynamic, dynamic> result =
          await platform.invokeMethod('getUpgradeConfig');
      return Map<String, dynamic>.from(result);
    } catch (e) {
      debugPrint('Platform method failed: $e');
      rethrow;
    }
  }

  static Future<void> upgradeToTier(int tier) async {
    try {
      await platform.invokeMethod('upgradeToTier', {'tier': tier});
    } catch (e) {
      debugPrint('Platform method failed: $e');
      rethrow;
    }
  }

  static Future<void> deferUpgradePrompt30Days() async {
    try {
      await platform.invokeMethod('deferUpgradePrompt30Days');
    } catch (e) {
      debugPrint('Platform method failed: $e');
      rethrow;
    }
  }

  static Future<void> setUpgradePromptDisabled(bool disabled) async {
    try {
      await platform.invokeMethod('setUpgradePromptDisabled', {
        'disabled': disabled,
      });
    } catch (e) {
      debugPrint('Platform method failed: $e');
      rethrow;
    }
  }
}
