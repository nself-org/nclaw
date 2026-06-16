import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'wizard_state.dart';

// ---------------------------------------------------------------------------
// Static data
// ---------------------------------------------------------------------------

/// IANA timezone identifiers shown in the picker.
const _timezones = [
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Phoenix',
  'America/Anchorage',
  'Pacific/Honolulu',
  'Europe/London',
  'Europe/Paris',
  'Europe/Berlin',
  'Europe/Helsinki',
  'Asia/Dubai',
  'Asia/Kolkata',
  'Asia/Tokyo',
  'Asia/Shanghai',
  'Australia/Sydney',
];

/// Wake-time options shown in the picker.
const _wakeTimes = [
  '05:00', '05:30', '06:00', '06:30',
  '07:00', '07:30', '08:00', '08:30',
  '09:00', '09:30', '10:00',
];

// ---------------------------------------------------------------------------
// Screen 4 — Scheduler Setup
// ---------------------------------------------------------------------------

/// Screen 4 of the first-run bootstrap wizard.
///
/// Only shown when the cron plugin was selected on Screen 3.
/// Captures timezone, wake time, and three starter recipe toggles.
///
/// Accessibility (WCAG 2.1 AA):
/// - Dropdowns have visible labels; screen readers read via [DropdownButtonFormField]
///   semantics which carries label text automatically.
/// - Recipe checkboxes use [CheckboxListTile] which provides role=checkbox + label.
/// - Focus moves here when the screen becomes active (managed by parent wizard).
class Screen4Scheduler extends ConsumerWidget {
  final VoidCallback onContinue;
  final VoidCallback onBack;

  const Screen4Scheduler({
    super.key,
    required this.onContinue,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wizard = ref.watch(wizardStateProvider);
    final notifier = ref.read(wizardStateProvider.notifier);
    final theme = Theme.of(context);

    // Use existing schedule or default.
    final schedule = wizard.schedule ?? const WizardSchedule();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Daily Schedule',
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'ɳClaw will run these automatically using your cron plugin.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 20),
        // Timezone picker
        DropdownButtonFormField<String>(
          key: const Key('screen4-timezone'),
          initialValue: schedule.timezone,
          decoration: const InputDecoration(
            labelText: 'Timezone',
            border: OutlineInputBorder(),
          ),
          items: _timezones
              .map((tz) =>
                  DropdownMenuItem(value: tz, child: Text(tz)))
              .toList(),
          onChanged: (val) {
            if (val != null) {
              notifier.setSchedule(schedule.copyWith(timezone: val));
            }
          },
        ),
        const SizedBox(height: 16),
        // Wake-time picker
        DropdownButtonFormField<String>(
          key: const Key('screen4-wake-time'),
          initialValue: _wakeTimes.contains(schedule.wakeTime)
              ? schedule.wakeTime
              : '07:30',
          decoration: const InputDecoration(
            labelText: 'Wake time',
            border: OutlineInputBorder(),
          ),
          items: _wakeTimes
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: (val) {
            if (val != null) {
              notifier.setSchedule(schedule.copyWith(wakeTime: val));
            }
          },
        ),
        const SizedBox(height: 20),
        Text(
          'Starter recipes',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        // Morning Briefing
        CheckboxListTile(
          key: const Key('screen4-morning-briefing'),
          title: const Text('Morning Briefing'),
          subtitle: Text(
            'News + agenda at ${_recipeTime(schedule.wakeTime, 0)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          value: schedule.morningBriefing,
          contentPadding: EdgeInsets.zero,
          onChanged: (val) {
            notifier.setSchedule(
                schedule.copyWith(morningBriefing: val ?? true));
          },
        ),
        // End-of-Day Summary
        CheckboxListTile(
          key: const Key('screen4-eod-summary'),
          title: const Text('End-of-Day Summary'),
          subtitle: Text(
            'Wrap-up at ${_recipeTime(schedule.wakeTime, 10)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          value: schedule.eodSummary,
          contentPadding: EdgeInsets.zero,
          onChanged: (val) {
            notifier.setSchedule(
                schedule.copyWith(eodSummary: val ?? true));
          },
        ),
        // Weekly Review
        CheckboxListTile(
          key: const Key('screen4-weekly-review'),
          title: const Text('Weekly Review'),
          subtitle: Text(
            'Sunday at 19:00',
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          value: schedule.weeklyReview,
          contentPadding: EdgeInsets.zero,
          onChanged: (val) {
            notifier.setSchedule(
                schedule.copyWith(weeklyReview: val ?? false));
          },
        ),
        const Spacer(),
        // Navigation buttons — reachable via Tab after all inputs (DOM order)
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('screen4-back'),
                onPressed: onBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('screen4-continue'),
                onPressed: onContinue,
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Derives an approximate display time offset from [wakeTime].
  /// [offsetHours] is added to produce eod time.
  String _recipeTime(String wakeTime, int offsetHours) {
    final parts = wakeTime.split(':');
    if (parts.length != 2) return wakeTime;
    final h = (int.tryParse(parts[0]) ?? 7) + offsetHours;
    final m = int.tryParse(parts[1]) ?? 30;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}
