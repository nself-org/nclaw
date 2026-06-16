import 'package:flutter/material.dart';

/// AIDisclosureBanner — EU AI Act disclosure for ɳClaw (S50-T17)
///
/// Persistent banner shown in the app indicating that responses are AI-generated.
/// Required by the EU AI Act (Regulation (EU) 2024/1689) for AI systems
/// interacting with users.
///
/// This banner is shown persistently in the conversation interface.
/// It does NOT block interaction.
///
/// Usage:
///   AIDisclosureBanner(
///     onLearnMore: () => launchUrl(Uri.parse('https://nself.org/legal/ai-aup')),
///   )
class AIDisclosureBanner extends StatelessWidget {
  /// Called when the user taps the "Learn more" link.
  final VoidCallback? onLearnMore;

  /// If true, show a compact single-line version (for narrow layouts).
  final bool compact;

  const AIDisclosureBanner({
    super.key,
    this.onLearnMore,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (compact) {
      return _buildCompact(context, theme, colorScheme);
    }
    return _buildFull(context, theme, colorScheme);
  }

  Widget _buildFull(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 14,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Powered by AI — responses may be inaccurate. Verify important information.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (onLearnMore != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onLearnMore,
              child: Text(
                'Learn more',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompact(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 12,
            color: colorScheme.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 4),
          Text(
            'AI-powered',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
