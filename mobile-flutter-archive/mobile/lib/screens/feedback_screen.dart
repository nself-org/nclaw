/// F-28-13: In-app feedback form.
///
/// Settings > "Send Feedback" opens this form.
/// Submits to POST /claw/feedback with app version, platform, OS,
/// optional screenshot, optional email.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/connection_provider.dart';

class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _messageController = TextEditingController();
  final _emailController = TextEditingController();
  String _category = 'general';
  Uint8List? _screenshot;
  bool _submitting = false;

  static const _categories = [
    ('general', 'General Feedback'),
    ('bug', 'Bug Report'),
    ('feature', 'Feature Request'),
    ('performance', 'Performance Issue'),
  ];

  @override
  void dispose() {
    _messageController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 80,
    );
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() => _screenshot = bytes);
    }
  }

  Future<void> _submit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your feedback')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final serverUrl =
          ref.read(connectionProvider).activeServer?.url;
      if (serverUrl == null) throw Exception('Not connected to server');

      final info = await PackageInfo.fromPlatform();

      final body = <String, dynamic>{
        'message': message,
        'category': _category,
        'app_version': info.version,
        'build_number': info.buildNumber,
        'platform': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
      };

      final email = _emailController.text.trim();
      if (email.isNotEmpty) body['email'] = email;

      if (_screenshot != null) {
        body['screenshot'] = base64Encode(_screenshot!);
      }

      final response = await http.post(
        Uri.parse('$serverUrl/claw/feedback'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feedback sent. Thank you!')),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send (${response.statusCode})')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Feedback'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Category selector.
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            items: _categories
                .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _category = v);
            },
          ),
          const SizedBox(height: 16),

          // Message.
          TextField(
            controller: _messageController,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Your feedback',
              hintText: 'Tell us what you think, report a bug, or suggest a feature...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),

          // Optional email.
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email (optional)',
              hintText: 'For follow-up questions',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Screenshot.
          OutlinedButton.icon(
            onPressed: _pickScreenshot,
            icon: const Icon(Icons.screenshot),
            label: Text(_screenshot != null
                ? 'Screenshot attached (${(_screenshot!.length / 1024).toStringAsFixed(0)} KB)'
                : 'Attach screenshot (optional)'),
          ),
          if (_screenshot != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _screenshot!,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _screenshot = null),
              child: const Text('Remove screenshot'),
            ),
          ],

          const SizedBox(height: 24),

          // Info note.
          Text(
            'Your feedback will include: app version, platform, and OS version. '
            'No personal data is collected unless you provide your email.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
