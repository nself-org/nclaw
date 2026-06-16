/// S21-T05: Reusable empty-state widget.
///
/// One component to cover all seven UI states where a screen has no data:
/// empty (first-time), loaded-empty, error, offline, loading, forbidden,
/// and search-empty. Drop into any screen to keep visual language consistent.
///
/// Example:
/// ```dart
/// EmptyState.firstTime(
///   icon: Icons.chat_bubble_outline,
///   title: 'Start your first chat',
///   message: 'Your conversations stay private and build memory over time.',
///   primaryAction: EmptyStateAction(
///     label: 'New chat',
///     icon: Icons.add,
///     onPressed: () => ...,
///   ),
/// );
/// ```
library;

import 'package:flutter/material.dart';

import '../theme/brand_theme.dart';

/// Action button spec for empty states.
class EmptyStateAction {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool filled;

  const EmptyStateAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = true,
  });
}

/// Visual tone of the empty state — controls icon color + subtle styling.
enum EmptyStateTone { neutral, error, offline, info }

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final EmptyStateAction? primaryAction;
  final EmptyStateAction? secondaryAction;
  final EmptyStateTone tone;

  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.primaryAction,
    this.secondaryAction,
    this.tone = EmptyStateTone.neutral,
    super.key,
  });

  /// First-time / no-data-yet variant.
  factory EmptyState.firstTime({
    required IconData icon,
    required String title,
    String? message,
    EmptyStateAction? primaryAction,
    EmptyStateAction? secondaryAction,
    Key? key,
  }) =>
      EmptyState(
        key: key,
        icon: icon,
        title: title,
        message: message,
        primaryAction: primaryAction,
        secondaryAction: secondaryAction,
        tone: EmptyStateTone.neutral,
      );

  /// Error variant — includes a retry action by convention.
  factory EmptyState.error({
    required String title,
    String? message,
    required VoidCallback onRetry,
    String retryLabel = 'Try again',
    Key? key,
  }) =>
      EmptyState(
        key: key,
        icon: Icons.error_outline,
        title: title,
        message: message,
        tone: EmptyStateTone.error,
        primaryAction: EmptyStateAction(
          label: retryLabel,
          icon: Icons.refresh,
          onPressed: onRetry,
          filled: false,
        ),
      );

  /// Offline variant.
  factory EmptyState.offline({
    String title = "You're offline",
    String? message =
        'Changes will sync once the connection is restored.',
    VoidCallback? onRetry,
    Key? key,
  }) =>
      EmptyState(
        key: key,
        icon: Icons.cloud_off_outlined,
        title: title,
        message: message,
        tone: EmptyStateTone.offline,
        primaryAction: onRetry == null
            ? null
            : EmptyStateAction(
                label: 'Retry',
                icon: Icons.refresh,
                onPressed: onRetry,
                filled: false,
              ),
      );

  /// Search-empty variant.
  factory EmptyState.noResults({
    required String query,
    String? message,
    VoidCallback? onClear,
    Key? key,
  }) =>
      EmptyState(
        key: key,
        icon: Icons.search_off,
        title: 'No results for "$query"',
        message: message ?? 'Try a different search term.',
        tone: EmptyStateTone.info,
        primaryAction: onClear == null
            ? null
            : EmptyStateAction(
                label: 'Clear search',
                onPressed: onClear,
                filled: false,
              ),
      );

  Color _iconColor(BuildContext context) {
    return switch (tone) {
      EmptyStateTone.error => BrandColors.error,
      EmptyStateTone.offline => BrandColors.warning,
      EmptyStateTone.info => BrandColors.info,
      EmptyStateTone.neutral => BrandColors.primary.withValues(alpha: 0.7),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = _iconColor(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(BrandSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 36, color: iconColor),
              ),
              const SizedBox(height: BrandSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: BrandColors.textHigh,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: BrandSpacing.sm),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: BrandColors.textMedium,
                    height: 1.45,
                  ),
                ),
              ],
              if (primaryAction != null || secondaryAction != null) ...[
                const SizedBox(height: BrandSpacing.xl),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: BrandSpacing.md,
                  runSpacing: BrandSpacing.sm,
                  children: [
                    if (primaryAction != null)
                      _buildActionButton(primaryAction!),
                    if (secondaryAction != null)
                      _buildActionButton(secondaryAction!),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(EmptyStateAction action) {
    final icon = action.icon;
    if (action.filled) {
      if (icon != null) {
        return FilledButton.icon(
          onPressed: action.onPressed,
          icon: Icon(icon, size: 18),
          label: Text(action.label),
        );
      }
      return FilledButton(
        onPressed: action.onPressed,
        child: Text(action.label),
      );
    }
    if (icon != null) {
      return FilledButton.tonalIcon(
        onPressed: action.onPressed,
        icon: Icon(icon, size: 18),
        label: Text(action.label),
      );
    }
    return FilledButton.tonal(
      onPressed: action.onPressed,
      child: Text(action.label),
    );
  }
}
