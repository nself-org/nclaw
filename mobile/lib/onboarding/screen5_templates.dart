import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'wizard_state.dart';

// ---------------------------------------------------------------------------
// Template definitions
// ---------------------------------------------------------------------------

class _TemplateInfo {
  final String id;
  final String label;
  final String description;
  final IconData icon;

  const _TemplateInfo({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
  });
}

const _templates = [
  _TemplateInfo(
    id: kTemplatePersonalAssistant,
    label: 'Personal Assistant',
    description: 'Email, calendar, tasks — your daily operations hub.',
    icon: Icons.person_outline,
  ),
  _TemplateInfo(
    id: kTemplateResearchAgent,
    label: 'Research Agent',
    description: 'Web, papers, summarize — deep-dive on any topic.',
    icon: Icons.search_outlined,
  ),
  _TemplateInfo(
    id: kTemplateWritingCoach,
    label: 'Writing Coach',
    description: 'Edit, suggest, rewrite — sharpen every sentence.',
    icon: Icons.edit_outlined,
  ),
  _TemplateInfo(
    id: kTemplateCodeReviewer,
    label: 'Code Reviewer',
    description: 'Diff analysis, PRs, security — precision code review.',
    icon: Icons.code_outlined,
  ),
  _TemplateInfo(
    id: kTemplateCustom,
    label: 'Custom',
    description: 'Start blank and configure everything yourself.',
    icon: Icons.tune_outlined,
  ),
];

// ---------------------------------------------------------------------------
// Screen 5 — Agent Templates
// ---------------------------------------------------------------------------

/// Screen 5 of the first-run bootstrap wizard.
///
/// Presents 5 agent template radio options. Selecting one and tapping
/// [Finish Setup] triggers [onFinish], which calls [wizard_complete.dart].
///
/// Accessibility (WCAG 2.1 AA):
/// - Radio group wrapped in [Semantics] with [role="radiogroup"] and label.
/// - Each option's description text is inline (always visible; not just aria-describedby).
/// - Back and Finish buttons are last in DOM order after all radio inputs.
/// - Focus moves to first radio when screen becomes active (managed by parent).
class Screen5Templates extends ConsumerWidget {
  final VoidCallback onFinish;
  final VoidCallback onBack;

  const Screen5Templates({
    super.key,
    required this.onFinish,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wizard = ref.watch(wizardStateProvider);
    final notifier = ref.read(wizardStateProvider.notifier);
    final theme = Theme.of(context);

    // Default to Personal Assistant if nothing chosen yet.
    final selected =
        wizard.agentTemplate ?? kTemplatePersonalAssistant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose Your Agent Style',
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Sets your agent name, persona, and default tools. Change anytime.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color:
                theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 16),
        // Radio group — role="radiogroup" + aria-label via Semantics
        Semantics(
          label: 'Agent style',
          child: Column(
            children: _templates.map((t) {
              final isSelected = selected == t.id;
              return _TemplateRadioTile(
                template: t,
                isSelected: isSelected,
                onSelect: () => notifier.setTemplate(t.id),
              );
            }).toList(),
          ),
        ),
        const Spacer(),
        // Navigation buttons — last in DOM order per WCAG 2.1 guideline
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('screen5-back'),
                onPressed: onBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('screen5-finish'),
                onPressed: onFinish,
                child: const Text('Finish Setup'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Template radio tile
// ---------------------------------------------------------------------------

class _TemplateRadioTile extends StatelessWidget {
  final _TemplateInfo template;
  final bool isSelected;
  final VoidCallback onSelect;

  const _TemplateRadioTile({
    required this.template,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      // role=radio inferred from Radio widget; label covers name + description
      label: '${template.label}. ${template.description}',
      inMutuallyExclusiveGroup: true,
      child: RadioListTile<bool>(
        key: Key('template-${template.id}'),
        value: true,
        groupValue: isSelected,
        onChanged: (_) => onSelect(),
        contentPadding: EdgeInsets.zero,
        secondary: Icon(
          template.icon,
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withValues(alpha: 0.45),
        ),
        title: Text(
          template.label,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight:
                isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        // Description is inline (always visible), not hidden behind aria-describedby
        subtitle: Text(
          template.description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}
