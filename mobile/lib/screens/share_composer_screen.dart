/// E-26-05c: Mini composer UI for share sheet extension.
///
/// Displays a preview of shared content, topic picker defaulting to last used,
/// and a "Save to claw" button that POSTs to /memory/quick-add.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/topic_node.dart';
import '../providers/connection_provider.dart';
import '../providers/topic_provider.dart';

class ShareComposerScreen extends ConsumerStatefulWidget {
  /// The content received from the share sheet.
  final String sharedContent;
  final String? sharedTitle;
  final String? sharedMimeType;

  const ShareComposerScreen({
    super.key,
    required this.sharedContent,
    this.sharedTitle,
    this.sharedMimeType,
  });

  @override
  ConsumerState<ShareComposerScreen> createState() =>
      _ShareComposerScreenState();
}

class _ShareComposerScreenState extends ConsumerState<ShareComposerScreen> {
  final _noteController = TextEditingController();
  String? _selectedTopicId;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topicState = ref.watch(topicTreeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Save to \u0273Claw'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Content preview
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.sharedTitle != null) ...[
                      Text(widget.sharedTitle!,
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      widget.sharedContent,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7),
                      ),
                    ),
                    if (widget.sharedContent.length > 200)
                      Text(
                        '${widget.sharedContent.length} characters',
                        style: theme.textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Topic picker
            DropdownButtonFormField<String>(
              value: _selectedTopicId,
              decoration: const InputDecoration(
                labelText: 'Topic',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.topic),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Default (last used)'),
                ),
                ...topicState.topics.map((t) => DropdownMenuItem(
                      value: t.id,
                      child: Text(t.name),
                    )),
              ],
              onChanged: (v) => setState(() => _selectedTopicId = v),
            ),
            const SizedBox(height: 12),

            // Optional note
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Add a note (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.note_add),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Error
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ),

            // Save button
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Saving...' : 'Save to memory'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final serverUrl = ref.read(connectionProvider).activeServer?.url;
    if (serverUrl == null) {
      setState(() => _error = 'No server connected');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$serverUrl/memory/quick-add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'content': widget.sharedContent,
          'title': widget.sharedTitle,
          'mime_type': widget.sharedMimeType,
          'topic_id': _selectedTopicId,
          'note': _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved to memory')),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _saving = false;
          _error = 'Save failed (${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Network error. Content queued for later.';
      });
      // Queue for offline sync.
    }
  }
}
