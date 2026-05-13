// T-1108: ThreadTagChips — compact color-coded tag chips for session tags.
//
// Renders a Wrap of small chips for a list of session tags. Colors match the
// KNOWN_TAGS vocabulary from thread_intelligence.rs. Tappable when onTagTap
// is provided — used by ThreadListScreen to filter by tag.

import 'package:flutter/material.dart';

// Tag color palette — must stay in sync with _tagColors in thread_list_screen.dart
// and KNOWN_TAGS in plugins-pro/paid/claw/src/thread_intelligence.rs.
const _tagColors = <String, Color>{
  'code': Color(0xFF3B82F6),        // blue
  'infra': Color(0xFFF97316),       // orange
  'admin': Color(0xFFEF4444),       // red
  'personal': Color(0xFF22C55E),    // green
  'research': Color(0xFFA855F7),    // purple
  'question': Color(0xFF06B6D4),    // cyan
  'task': Color(0xFFEAB308),        // yellow
  'planning': Color(0xFF8B5CF6),    // violet
};

Color _colorForTag(String tag) =>
    _tagColors[tag] ?? const Color(0xFF6B7280); // grey fallback

/// A [Wrap] of small color-coded tag chips.
///
/// Each chip shows `#tag` in the tag's category color. When [onTagTap] is
/// provided, tapping a chip calls the callback with the tag string so the
/// parent can apply a filter.
///
/// Returns [SizedBox.shrink] when [tags] is empty.
class ThreadTagChips extends StatelessWidget {
  final List<String> tags;

  /// Optional callback invoked when the user taps a chip.
  final void Function(String tag)? onTagTap;

  const ThreadTagChips({super.key, required this.tags, this.onTagTap});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: tags
          .map((tag) => GestureDetector(
                onTap: onTagTap != null ? () => onTagTap!(tag) : null,
                child: Chip(
                  label: Text(
                    '#$tag',
                    style: const TextStyle(fontSize: 10),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  backgroundColor:
                      _colorForTag(tag).withValues(alpha: 0.12),
                  side: BorderSide(
                    color: _colorForTag(tag).withValues(alpha: 0.35),
                  ),
                  labelStyle: TextStyle(color: _colorForTag(tag)),
                ),
              ))
          .toList(),
    );
  }
}
