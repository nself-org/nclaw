import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';
import '../widgets/voice_chat_widget.dart';
import 'thread_list_screen.dart';

/// Full-screen chat UI for the nClaw AI assistant.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final serverUrl =
        ref.read(connectionProvider).activeServer?.url ?? '';
    _textController.clear();

    ref.read(chatProvider.notifier).sendMessage(text, serverUrl);
  }

  void _showSessionList(BuildContext context) {
    final sessions = ref.read(chatSessionsProvider);
    final activeId = ref.read(chatProvider).activeSessionId;

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Sessions',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New'),
                  onPressed: () {
                    ref.read(chatProvider.notifier).newSession();
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: sessions.length,
              itemBuilder: (_, index) {
                final session = sessions[index];
                final isActive = session.id == activeId;
                return ListTile(
                  leading: Icon(
                    Icons.chat_bubble_outline,
                    color: isActive
                        ? Theme.of(ctx).colorScheme.primary
                        : null,
                  ),
                  title: Text(session.displayTitle),
                  subtitle: Text(
                    '${session.messages.length} message${session.messages.length == 1 ? '' : 's'}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  trailing: isActive
                      ? Icon(Icons.check,
                          color: Theme.of(ctx).colorScheme.primary)
                      : null,
                  onTap: () {
                    ref
                        .read(chatProvider.notifier)
                        .switchSession(session.id);
                    Navigator.of(ctx).pop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final messages = chatState.messages;
    final isStreaming = chatState.isStreaming;
    final sessionTitle = chatState.activeSession?.displayTitle ?? '\u014BClaw';
    final parentSession = chatState.parentSession;
    final activeId = chatState.activeSessionId;
    final sessionTags = chatState.activeSession?.tags ?? const [];
    final breakout = chatState.breakoutSuggestion;

    return Scaffold(
      appBar: AppBar(
        title: Text(sessionTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'Sessions',
            onPressed: () => _showSessionList(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        onPressed: () => ref.read(chatProvider.notifier).newSession(),
        tooltip: 'New session',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Breadcrumb bar — shown when this session is a branch.
          if (parentSession != null)
            _BreadcrumbBar(
              parentTitle: parentSession.displayTitle,
              onTap: () => ref
                  .read(chatProvider.notifier)
                  .switchSession(parentSession.id),
            ),
          // Drift-detection banner — animates in/out.
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: breakout != null
                ? _BreakoutBanner(
                    suggestion: breakout,
                    onBranch: activeId != null
                        ? () => ref
                            .read(chatProvider.notifier)
                            .branchSession(activeId)
                        : null,
                    onDismiss: () =>
                        ref.read(chatProvider.notifier).dismissBreakout(),
                  )
                : const SizedBox.shrink(),
          ),
          // Active session tag chips — tap to filter ThreadListScreen.
          if (sessionTags.isNotEmpty)
            _SessionTagsBar(
              tags: sessionTags,
              onTagTap: (tag) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ThreadListScreen(initialTagFilter: tag),
                ),
              ),
            ),
          Expanded(
            child: messages.isEmpty
                ? _EmptyChat(isStreaming: isStreaming)
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      // Reversed list — index 0 is the last message.
                      final msg =
                          messages[messages.length - 1 - index];
                      return _MessageBubble(
                        message: msg,
                        onBranch: activeId != null
                            ? () => ref
                                .read(chatProvider.notifier)
                                .branchSession(activeId)
                            : null,
                      );
                    },
                  ),
          ),
          _InputBar(
            controller: _textController,
            isStreaming: isStreaming,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }
}

/// Empty state shown when there are no messages yet.
class _EmptyChat extends StatelessWidget {
  final bool isStreaming;

  const _EmptyChat({required this.isStreaming});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isStreaming) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'Ask \u014BClaw anything',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single message bubble (user on right, assistant on left).
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  /// Called when the user selects "Branch from here". Null disables the option.
  final VoidCallback? onBranch;

  const _MessageBubble({required this.message, this.onBranch});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final theme = Theme.of(context);

    return GestureDetector(
      onLongPress: () {
        showModalBottomSheet<void>(
          context: context,
          builder: (ctx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              if (onBranch != null)
                ListTile(
                  leading: const Icon(Icons.call_split_outlined),
                  title: const Text('Branch from here'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onBranch!();
                  },
                ),
            ],
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: isUser
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isUser) ...[
                  CircleAvatar(
                    radius: 14,
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.2),
                    child: Icon(
                      Icons.smart_toy_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: isUser
                      ? _UserBubble(content: message.content, theme: theme)
                      : _AssistantBubble(
                          content: message.content, theme: theme),
                ),
                if (isUser) const SizedBox(width: 8),
              ],
            ),
            if (!isUser && message.tierSource != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: _TierBadge(
                  tierSource: message.tierSource!,
                  latencyMs: message.latencyMs,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// User message chip (indigo, right-aligned).
class _UserBubble extends StatelessWidget {
  final String content;
  final ThemeData theme;

  const _UserBubble({required this.content, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Text(
        content,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
  }
}

/// Assistant message card (dark, left-aligned).
class _AssistantBubble extends StatelessWidget {
  final String content;
  final ThemeData theme;

  const _AssistantBubble({required this.content, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
      ),
      child: Text(
        content,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Small badge showing which AI tier/model served the response.
///
/// Color coding:
///   local         → green
///   free / gemini → blue
///   api_key       → orange
///   default       → grey
class _TierBadge extends StatelessWidget {
  final String tierSource;
  final int? latencyMs;

  const _TierBadge({required this.tierSource, this.latencyMs});

  Color _badgeColor(BuildContext context) {
    final lower = tierSource.toLowerCase();
    if (lower.contains('local') || lower.contains('phi')) {
      return Colors.green;
    }
    if (lower.contains('free') ||
        lower.contains('gemini') ||
        lower.contains('flash')) {
      return Colors.blue;
    }
    if (lower.contains('api') ||
        lower.contains('claude') ||
        lower.contains('openai') ||
        lower.contains('gpt')) {
      return Colors.orange;
    }
    return Colors.grey;
  }

  String _label() {
    final latency = latencyMs != null
        ? ' \u2022 ${(latencyMs! / 1000).toStringAsFixed(1)}s'
        : '';
    return '$tierSource$latency';
  }

  @override
  Widget build(BuildContext context) {
    final color = _badgeColor(context);

    return Chip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      backgroundColor: color.withValues(alpha: 0.12),
      label: Text(
        _label(),
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Bottom input bar with text field, mic button, and send/loading button.
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isStreaming;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.isStreaming,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            // Mic button — opens VoiceChatWidget overlay.
            VoiceMicButton(
              onTranscript: (text) {
                controller.text = text;
                controller.selection = TextSelection.collapsed(
                  offset: text.length,
                );
              },
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Message \u014BClaw...',
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.4),
                  ),
                  filled: true,
                  fillColor:
                      theme.colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) {
                  if (!isStreaming) onSend();
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: isStreaming
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : IconButton.filled(
                      icon: const Icon(Icons.send, size: 20),
                      onPressed: onSend,
                      tooltip: 'Send',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Breadcrumb bar shown at the top of the chat body when the active session
/// is a branch of another session. Tapping navigates back to the parent.
class _BreadcrumbBar extends StatelessWidget {
  final String parentTitle;
  final VoidCallback onTap;

  const _BreadcrumbBar({required this.parentTitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: theme.colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            Icon(Icons.subdirectory_arrow_left,
                size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                parentTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Text(
              ' / Branch',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Breakout suggestion banner
// ---------------------------------------------------------------------------

/// Animated banner shown when the backend detects topic drift.
///
/// [New Thread] calls [onBranch] to start a sub-session.
/// [✕] calls [onDismiss] to suppress the banner.
class _BreakoutBanner extends StatelessWidget {
  final BreakoutSuggestion suggestion;
  final VoidCallback? onBranch;
  final VoidCallback onDismiss;

  const _BreakoutBanner({
    required this.suggestion,
    required this.onBranch,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.tertiary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.call_split_outlined, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'New topic: ${suggestion.newTopic}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: accent),
            ),
          ),
          const SizedBox(width: 8),
          if (onBranch != null)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: accent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onBranch,
              child: const Text('New Thread'),
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: accent.withValues(alpha: 0.7),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onDismiss,
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Session tag chips bar
// ---------------------------------------------------------------------------

/// Horizontal scrollable colour-coded tag chips for the active session.
///
/// Tapping a chip pushes [ThreadListScreen] pre-filtered to that tag.
class _SessionTagsBar extends StatelessWidget {
  final List<String> tags;
  final ValueChanged<String> onTagTap;

  const _SessionTagsBar({required this.tags, required this.onTagTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: tags.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final tag = tags[i];
          final color = _tagColor(tag);
          return ActionChip(
            label: Text(
              tag,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
            backgroundColor: color.withValues(alpha: 0.12),
            side: BorderSide(color: color.withValues(alpha: 0.35)),
            onPressed: () => onTagTap(tag),
          );
        },
      ),
    );
  }

  static Color _tagColor(String tag) {
    switch (tag) {
      case 'code':     return const Color(0xFF3B82F6);
      case 'infra':    return const Color(0xFFF97316);
      case 'admin':    return const Color(0xFFEF4444);
      case 'personal': return const Color(0xFF22C55E);
      case 'research': return const Color(0xFFA855F7);
      case 'question': return const Color(0xFF06B6D4);
      case 'task':     return const Color(0xFFEAB308);
      case 'planning': return const Color(0xFF8B5CF6);
      default:         return const Color(0xFF6B7280);
    }
  }
}
