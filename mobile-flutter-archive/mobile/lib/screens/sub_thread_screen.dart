// T-1107: SubThreadScreen — branch session with parent breadcrumb navigation.
//
// Wraps ChatScreen for a branch session and adds a breadcrumb bar at the top
// showing "Parent Title > Branch Title". Tapping the parent segment navigates
// back to the parent session.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_provider.dart';
import 'chat_screen.dart';

/// A wrapper screen for branch (sub-thread) sessions.
///
/// Shows a breadcrumb bar: "{parent title}  >  {branch title}" above the chat.
/// Tapping the parent title portion switches back to the parent session and
/// pops this screen.
class SubThreadScreen extends ConsumerWidget {
  /// The id of the branch session to display.
  final String sessionId;

  const SubThreadScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider);

    // Resolve the branch session and its parent.
    final branchSession =
        chatState.sessions.where((s) => s.id == sessionId).firstOrNull;
    final parentSession = branchSession?.parentSessionId != null
        ? chatState.sessions
            .where((s) => s.id == branchSession!.parentSessionId)
            .firstOrNull
        : null;

    final branchTitle = branchSession?.displayTitle ?? '\u0273Claw Branch';
    final parentTitle = parentSession?.displayTitle ?? 'Parent Thread';

    return Column(
      children: [
        _BreadcrumbBar(
          parentTitle: parentTitle,
          branchTitle: branchTitle,
          onParentTap: () async {
            if (parentSession != null) {
              await ref
                  .read(chatProvider.notifier)
                  .switchSession(parentSession.id);
            }
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
        const Expanded(child: ChatScreen()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Breadcrumb bar
// ---------------------------------------------------------------------------

class _BreadcrumbBar extends StatelessWidget {
  final String parentTitle;
  final String branchTitle;
  final VoidCallback onParentTap;

  const _BreadcrumbBar({
    required this.parentTitle,
    required this.branchTitle,
    required this.onParentTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurface.withValues(alpha: 0.45);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Parent segment — tappable
            GestureDetector(
              onTap: onParentTap,
              child: Text(
                parentTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.chevron_right, size: 14, color: dim),
            ),
            // Branch segment
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.call_split_outlined, size: 12, color: dim),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      branchTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: dim),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
