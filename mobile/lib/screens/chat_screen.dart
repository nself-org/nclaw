import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as markdownpkg;
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:shimmer/shimmer.dart';

import '../providers/chat_provider.dart';
import '../providers/connection_provider.dart';
import '../services/tts_service.dart';
import '../providers/voice_settings_provider.dart';
import '../widgets/voice_chat_widget.dart';
import 'digest_viewer_screen.dart';
import 'memories_screen.dart';
import 'proactive_settings_screen.dart';
import 'thread_list_screen.dart';
import 'voice_conversation_screen.dart';
import 'voice_settings_screen.dart';

/// Full-screen chat UI for the nClaw AI assistant.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // TTS state ----------------------------------------------------------------
  final TtsService _tts = TtsService();
  String? _playingMessageId;
  // Pending sentences for sentence-by-sentence streaming TTS.
  final List<String> _ttsSentenceQueue = [];
  bool _ttsBusy = false;

  // Auto-play: play the last assistant message when streaming completes.
  // Toggled from voice settings (T-1115). Defaults to off.
  // ignore: prefer_final_fields — will be mutated by VoiceSettingsScreen (T-1115)
  bool _autoPlay = false;

  // Message editing state (T-7562).
  final TextEditingController _editController = TextEditingController();

  // Sentence splitter — splits on . ! ? followed by whitespace or end.
  static final RegExp _sentenceEnd = RegExp(r'(?<=[.!?])\s+');

  @override
  void initState() {
    super.initState();
    _tts.initialize();
    _tts.onComplete(_onTtsComplete);
  }

  @override
  void dispose() {
    _tts.stop();
    _textController.dispose();
    _editController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // TTS helpers
  // -------------------------------------------------------------------------

  void _onTtsComplete() {
    if (_ttsSentenceQueue.isNotEmpty) {
      final next = _ttsSentenceQueue.removeAt(0);
      _tts.speak(next);
    } else {
      if (mounted) setState(() { _ttsBusy = false; });
    }
  }

  /// Speak a full text as a sentence queue. Sets [_playingMessageId].
  Future<void> _playMessage(String messageId, String text) async {
    await _tts.stop();
    final sentences = text
        .split(_sentenceEnd)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (sentences.isEmpty) return;
    setState(() {
      _playingMessageId = messageId;
      _ttsBusy = true;
      _ttsSentenceQueue
        ..clear()
        ..addAll(sentences.skip(1));
    });
    await _tts.speak(sentences.first);
  }

  Future<void> _stopTts() async {
    await _tts.stop();
    setState(() {
      _playingMessageId = null;
      _ttsBusy = false;
      _ttsSentenceQueue.clear();
    });
  }

  void _onStreamingComplete(List<ChatMessage> messages) {
    if (!_autoPlay) return;
    final last = messages.lastWhere(
      (m) => m.role == 'assistant',
      orElse: () => messages.last,
    );
    if (last.role == 'assistant' && last.content.isNotEmpty) {
      _playMessage(last.id, last.content);
    }
  }

  // -------------------------------------------------------------------------

  void _showEditDialog(BuildContext context, ChatMessage msg, String sessionId) {
    _editController.text = msg.content;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: _editController,
          maxLines: 6,
          minLines: 2,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newText = _editController.text.trim();
              if (newText.isNotEmpty && newText != msg.content) {
                ref.read(chatProvider.notifier).editMessage(
                    sessionId, msg.id, newText);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _stopTts(); // stop any playing TTS when user sends a new message

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
    final sessionTitle = chatState.activeSession?.displayTitle ?? '\u0273Claw';
    final parentSession = chatState.parentSession;
    final activeId = chatState.activeSessionId;
    final sessionTags = chatState.activeSession?.tags ?? const [];
    final breakout = chatState.breakoutSuggestion;

    // Sync auto-play setting from provider into local state.
    _autoPlay = ref.watch(voiceSettingsProvider).autoPlay;

    // Auto-play: fire when streaming transitions to done.
    ref.listen<bool>(
      chatProvider.select((s) => s.isStreaming),
      (previous, current) {
        if (previous == true && current == false) {
          _onStreamingComplete(ref.read(chatProvider).messages);
        }
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(sessionTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology_outlined),
            tooltip: 'Memories',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MemoriesScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.summarize_outlined),
            tooltip: 'Daily Digest',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DigestViewerScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.schedule_outlined),
            tooltip: 'Proactive Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProactiveSettingsScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.mic_none_outlined),
            tooltip: 'Voice settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const VoiceSettingsScreen(),
              ),
            ),
          ),
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
                    itemCount: messages.length + (isStreaming ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Typing indicator at index 0 (bottom of reversed list).
                      if (isStreaming && index == 0) {
                        return const _TypingIndicator();
                      }
                      final msgIndex = isStreaming ? index - 1 : index;
                      // Reversed list — index 0 is the last message.
                      final msg =
                          messages[messages.length - 1 - msgIndex];
                      final isPlayingThis =
                          _playingMessageId == msg.id && _ttsBusy;
                      return _MessageReveal(
                        key: ValueKey(msg.id),
                        child: _MessageBubble(
                          message: msg,
                          isPlaying: isPlayingThis,
                          onPlayToggle: msg.role == 'assistant'
                              ? () {
                                  if (isPlayingThis) {
                                    _stopTts();
                                  } else {
                                    _playMessage(msg.id, msg.content);
                                  }
                                }
                              : null,
                          onBranch: activeId != null
                              ? () => ref
                                  .read(chatProvider.notifier)
                                  .branchSession(activeId)
                              : null,
                          onEdit: msg.role == 'user' && activeId != null
                              ? () => _showEditDialog(context, msg, activeId)
                              : null,
                          onDelete: activeId != null
                              ? () => ref
                                  .read(chatProvider.notifier)
                                  .deleteMessage(activeId, msg.id)
                              : null,
                          onRegenerate: msg.role == 'assistant' && activeId != null
                              ? () {
                                  final serverUrl =
                                      ref.read(connectionProvider).activeServer?.url ?? '';
                                  ref.read(chatProvider.notifier).regenerateLastResponse(serverUrl);
                                }
                              : null,
                        ),
                      );
                    },
                  ),
          ),
          _InputBar(
            controller: _textController,
            isStreaming: isStreaming,
            onSend: _sendMessage,
            onLongPressMic: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const VoiceConversationScreen(),
                fullscreenDialog: true,
              ),
            ),
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
      return Padding(
        padding: const EdgeInsets.all(24),
        child: _ShimmerLoader(),
      );
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
            'Ask \u0273Claw anything',
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

  /// Whether TTS is currently playing this message.
  final bool isPlaying;

  /// Called when the user taps the speaker icon. Null hides the button.
  final VoidCallback? onPlayToggle;

  /// Called when the user selects "Branch from here". Null disables the option.
  final VoidCallback? onBranch;

  /// Called when the user selects "Edit". Null hides the option.
  final VoidCallback? onEdit;

  /// Called when the user selects "Delete". Null hides the option.
  final VoidCallback? onDelete;

  /// Called when the user selects "Regenerate". Null hides the option.
  final VoidCallback? onRegenerate;

  const _MessageBubble({
    required this.message,
    this.isPlaying = false,
    this.onPlayToggle,
    this.onBranch,
    this.onEdit,
    this.onDelete,
    this.onRegenerate,
  });

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
              if (onEdit != null)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onEdit!();
                  },
                ),
              if (onRegenerate != null)
                ListTile(
                  leading: const Icon(Icons.refresh_outlined),
                  title: const Text('Regenerate'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onRegenerate!();
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
              if (onDelete != null)
                ListTile(
                  leading: Icon(Icons.delete_outline,
                      color: theme.colorScheme.error),
                  title: Text('Delete',
                      style: TextStyle(color: theme.colorScheme.error)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onDelete!();
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
                          content: message.content,
                          theme: theme,
                          isPlaying: isPlaying,
                        ),
                ),
                // Per-message TTS play/stop button (assistant only).
                if (onPlayToggle != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                      size: 18,
                    ),
                    color: isPlaying
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    tooltip: isPlaying ? 'Stop' : 'Play',
                    visualDensity: VisualDensity.compact,
                    onPressed: onPlayToggle,
                  ),
                ],
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
            if (!isUser && message.knowledgeUsed) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: _KnowledgeBadge(),
              ),
            ],
            if (!isUser && message.memoriesUsed > 0) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: _MemoriesBadge(
                  count: message.memoriesUsed,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MemoriesScreen(),
                    ),
                  ),
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

/// Assistant message card (dark, left-aligned) with markdown + syntax highlighting.
class _AssistantBubble extends StatelessWidget {
  final String content;
  final ThemeData theme;
  final bool isPlaying;

  const _AssistantBubble({
    required this.content,
    required this.theme,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
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
        border: isPlaying
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
                width: 1.5,
              )
            : null,
      ),
      child: MarkdownBody(
        data: content,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          code: theme.textTheme.bodySmall?.copyWith(
            backgroundColor: theme.colorScheme.surface,
            fontFamily: 'monospace',
          ),
          codeblockDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFF282C34),
          ),
        ),
        builders: {
          'code': _CodeBlockBuilder(),
        },
      ),
    );
  }
}

/// Custom markdown code block builder that uses flutter_highlight for syntax
/// coloring (T-7561).
class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(
      markdownpkg.Element element, TextStyle? preferredStyle) {
    // Only handle fenced code blocks (which have a 'language' attribute or
    // appear as block-level <code> inside <pre>).
    final language = element.attributes['language'] ?? '';
    final code = element.textContent;

    if (language.isEmpty && !code.contains('\n')) {
      // Inline code — let default rendering handle it.
      return null;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: HighlightView(
        code,
        language: language.isNotEmpty ? language : 'plaintext',
        theme: atomOneDarkTheme,
        padding: const EdgeInsets.all(12),
        textStyle: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
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

/// Small badge shown below assistant messages when the knowledge base was used.
class _KnowledgeBadge extends StatelessWidget {
  const _KnowledgeBadge();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Response informed by ɳSelf knowledge base',
      child: Chip(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
        avatar: Icon(Icons.menu_book_rounded,
            size: 12, color: cs.primary),
        side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
        backgroundColor: cs.primary.withValues(alpha: 0.08),
        label: Text(
          'docs used',
          style: TextStyle(
            fontSize: 11,
            color: cs.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Small badge shown below assistant messages when memories were injected.
class _MemoriesBadge extends StatelessWidget {
  const _MemoriesBadge({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: 'Tap to view memories',
        child: Chip(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
          avatar: Text('\u{1F9E0}',
              style: TextStyle(fontSize: 11, color: cs.tertiary)),
          side: BorderSide(color: cs.tertiary.withValues(alpha: 0.4)),
          backgroundColor: cs.tertiary.withValues(alpha: 0.08),
          label: Text(
            '$count ${count == 1 ? 'memory' : 'memories'} used',
            style: TextStyle(
              fontSize: 11,
              color: cs.tertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom input bar with text field, mic button, and send/loading button.
///
/// S21-T06: Simplified — 3 always-visible icons (attach, mic, send/stop)
/// plus an overflow menu for less-common actions.
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isStreaming;
  final VoidCallback onSend;
  final VoidCallback? onLongPressMic;
  final VoidCallback? onAttach;
  final VoidCallback? onCamera;
  final VoidCallback? onTemplates;

  const _InputBar({
    required this.controller,
    required this.isStreaming,
    required this.onSend,
    this.onLongPressMic,
    this.onAttach,
    this.onCamera,
    this.onTemplates,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            // Icon 1/3: Attach (with overflow menu for templates + camera).
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.add_circle_outline),
              onSelected: (value) {
                switch (value) {
                  case 'attach':
                    onAttach?.call();
                    break;
                  case 'camera':
                    onCamera?.call();
                    break;
                  case 'templates':
                    onTemplates?.call();
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'attach',
                  child: ListTile(
                    leading: Icon(Icons.attach_file),
                    title: Text('Attach file'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'camera',
                  child: ListTile(
                    leading: Icon(Icons.camera_alt_outlined),
                    title: Text('Camera'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'templates',
                  child: ListTile(
                    leading: Icon(Icons.bookmark_outline),
                    title: Text('Prompt templates'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            // Icon 2/3: Mic — tap: voice overlay; long-press: continuous mode.
            GestureDetector(
              onLongPress: onLongPressMic,
              child: VoiceMicButton(
                onTranscript: (text) {
                  controller.text = text;
                  controller.selection = TextSelection.collapsed(
                    offset: text.length,
                  );
                },
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Message \u0273Claw...',
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
        separatorBuilder: (_, __) => const SizedBox(width: 6),
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

// ---------------------------------------------------------------------------
// Message reveal animation (T-7565)
// ---------------------------------------------------------------------------

/// Wraps a message widget with a fade+slide-in animation on first build.
class _MessageReveal extends StatefulWidget {
  final Widget child;
  const _MessageReveal({super.key, required this.child});

  @override
  State<_MessageReveal> createState() => _MessageRevealState();
}

class _MessageRevealState extends State<_MessageReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Typing indicator (T-7566)
// ---------------------------------------------------------------------------

/// Animated "..." dots shown while waiting for AI response.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
            child: Icon(
              Icons.smart_toy_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final delay = i * 0.2;
                    final t = (_controller.value - delay).clamp(0.0, 1.0);
                    final bounce = (t < 0.5) ? t * 2 : (1.0 - t) * 2;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Transform.translate(
                        offset: Offset(0, -4 * bounce),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.3 + 0.4 * bounce),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shimmer skeleton loader (T-7570)
// ---------------------------------------------------------------------------

/// Skeleton placeholder shown instead of a spinner during initial streaming.
class _ShimmerLoader extends StatelessWidget {
  const _ShimmerLoader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest;
    final highlightColor = theme.colorScheme.surface;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerLine(width: double.infinity),
          const SizedBox(height: 10),
          _shimmerLine(width: 260),
          const SizedBox(height: 10),
          _shimmerLine(width: 200),
        ],
      ),
    );
  }

  Widget _shimmerLine({required double width}) {
    return Container(
      width: width,
      height: 14,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
