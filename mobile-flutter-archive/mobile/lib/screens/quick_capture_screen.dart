/// E-26-10a: Quick capture floating window content.
///
/// Shown when global hotkey is pressed or from tray menu.
/// Minimal composer with topic picker and send button.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../providers/connection_provider.dart';
import '../providers/topic_provider.dart';

class QuickCaptureScreen extends ConsumerStatefulWidget {
  const QuickCaptureScreen({super.key});

  @override
  ConsumerState<QuickCaptureScreen> createState() =>
      _QuickCaptureScreenState();
}

class _QuickCaptureScreenState extends ConsumerState<QuickCaptureScreen> {
  final _controller = TextEditingController();
  String? _selectedTopicId;
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topics = ref.watch(topicTreeProvider).topics;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Capture'),
        titleTextStyle: theme.textTheme.titleMedium,
        toolbarHeight: 40,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Topic dropdown (compact)
            DropdownButtonFormField<String>(
              value: _selectedTopicId,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Topic',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('Default')),
                ...topics.map((t) =>
                    DropdownMenuItem(value: t.id, child: Text(t.name))),
              ],
              onChanged: (v) => setState(() => _selectedTopicId = v),
            ),
            const SizedBox(height: 8),

            // Text input
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'What\'s on your mind?',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(height: 8),

            // Send button
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 16),
                  label: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final serverUrl = ref.read(connectionProvider).activeServer?.url;
    if (serverUrl == null) return;

    setState(() => _sending = true);

    try {
      final response = await http.post(
        Uri.parse('$serverUrl/claw/chat/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'content': text,
          'topic_id': _selectedTopicId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        HapticFeedback.mediumImpact();
        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() => _sending = false);
      }
    } catch (_) {
      setState(() => _sending = false);
    }
  }
}
