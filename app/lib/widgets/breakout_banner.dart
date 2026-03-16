// T-1108: BreakoutSuggestionBanner — dismissable banner shown when the backend
// detects significant topic drift in the current session (T-1103).
//
// Rendered inside ChatScreen above the input bar. Animates in/out with a
// vertical slide + fade. Tapping "Start" calls onAccept (branch session).
// Tapping ✕ calls onDismiss (suppress for 10 messages per T-1103 cooldown).

import 'package:flutter/material.dart';

/// A compact animated banner suggesting the user start a new thread.
///
/// Shown when [BreakoutSuggestion] arrives from the backend. The banner slides
/// in from below and fades out on dismiss.
///
/// Usage:
/// ```dart
/// if (breakout != null)
///   BreakoutSuggestionBanner(
///     suggestedTitle: breakout.newTopic,
///     onAccept: () => ref.read(chatProvider.notifier).branchSession(sessionId),
///     onDismiss: () => ref.read(chatProvider.notifier).dismissBreakout(),
///   )
/// ```
class BreakoutSuggestionBanner extends StatelessWidget {
  final String suggestedTitle;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const BreakoutSuggestionBanner({
    super.key,
    required this.suggestedTitle,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.fork_right, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Start new thread: "$suggestedTitle"?',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(onPressed: onAccept, child: const Text('Start')),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: onDismiss,
              tooltip: 'Dismiss',
            ),
          ],
        ),
      ),
    );
  }
}

/// An animated wrapper that slides the [BreakoutSuggestionBanner] in from
/// below when [visible] becomes true, and slides it out on false.
///
/// Use this in ChatScreen to avoid a jarring layout jump:
/// ```dart
/// AnimatedBreakoutBanner(
///   visible: cs.breakoutSuggestion != null,
///   suggestedTitle: cs.breakoutSuggestion?.newTopic ?? '',
///   onAccept: ...,
///   onDismiss: ...,
/// )
/// ```
class AnimatedBreakoutBanner extends StatefulWidget {
  final bool visible;
  final String suggestedTitle;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const AnimatedBreakoutBanner({
    super.key,
    required this.visible,
    required this.suggestedTitle,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  State<AnimatedBreakoutBanner> createState() => _AnimatedBreakoutBannerState();
}

class _AnimatedBreakoutBannerState extends State<AnimatedBreakoutBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slide = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    if (widget.visible) _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedBreakoutBanner old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) {
      _controller.forward();
    } else if (!widget.visible && old.visible) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (_controller.isDismissed) return const SizedBox.shrink();
        return FractionalTranslation(
          translation: Offset(0, _slide.value),
          child: FadeTransition(
            opacity: _fade,
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: BreakoutSuggestionBanner(
          suggestedTitle: widget.suggestedTitle,
          onAccept: widget.onAccept,
          onDismiss: widget.onDismiss,
        ),
      ),
    );
  }
}
