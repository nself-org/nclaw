// settings_screen_test.dart
// T-0448 — Flutter: widget tests for SettingsScreen
//
// Tests key interactions:
//   - Light/dark mode toggle
//   - API URL field (input + validation)
//   - Clear history button (tap + confirmation)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Stubs — replace with real imports when package structure is in place
// ---------------------------------------------------------------------------

class AppSettings {
  final String apiUrl;
  final bool isDarkMode;
  final String modelName;

  const AppSettings({
    required this.apiUrl,
    required this.isDarkMode,
    this.modelName = 'gpt-4',
  });

  AppSettings copyWith({String? apiUrl, bool? isDarkMode, String? modelName}) {
    return AppSettings(
      apiUrl: apiUrl ?? this.apiUrl,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      modelName: modelName ?? this.modelName,
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final void Function(AppSettings) onSettingsChanged;
  final Future<void> Function()? onClearHistory;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    this.onClearHistory,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _apiUrlController;
  late bool _isDarkMode;

  @override
  void initState() {
    super.initState();
    _apiUrlController = TextEditingController(text: widget.settings.apiUrl);
    _isDarkMode = widget.settings.isDarkMode;
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  bool _isValidUrl(String value) {
    if (value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', key: Key('settings-title')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dark mode toggle
            SwitchListTile(
              key: const Key('dark-mode-toggle'),
              title: const Text('Dark Mode'),
              value: _isDarkMode,
              onChanged: (value) {
                setState(() => _isDarkMode = value);
                widget.onSettingsChanged(
                  widget.settings.copyWith(isDarkMode: value),
                );
              },
            ),

            const SizedBox(height: 16),

            // API URL field
            TextFormField(
              key: const Key('api-url-field'),
              controller: _apiUrlController,
              decoration: const InputDecoration(
                labelText: 'API URL',
                hintText: 'https://api.example.com',
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) {
                if (value == null || !_isValidUrl(value)) {
                  return 'Please enter a valid URL (http:// or https://)';
                }
                return null;
              },
              onChanged: (value) {
                if (_isValidUrl(value)) {
                  widget.onSettingsChanged(
                    widget.settings.copyWith(apiUrl: value),
                  );
                }
              },
            ),

            const SizedBox(height: 32),

            // Clear history button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('clear-history-button'),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      key: const Key('clear-history-dialog'),
                      title: const Text('Clear History'),
                      content: const Text(
                        'All conversations will be permanently deleted. This cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          key: const Key('cancel-button'),
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          key: const Key('confirm-clear-button'),
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Clear All'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true && widget.onClearHistory != null) {
                    await widget.onClearHistory!();
                  }
                },
                child: const Text('Clear Conversation History'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final defaultSettings = const AppSettings(
    apiUrl: 'https://api.nself.org',
    isDarkMode: false,
  );

  group('SettingsScreen', () {
    // -------------------------------------------------------------------------
    // T-0448-08: renders without throwing
    // -------------------------------------------------------------------------

    testWidgets('renders without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settings: defaultSettings,
            onSettingsChanged: (_) {},
          ),
        ),
      );

      expect(find.byKey(const Key('settings-title')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // T-0448-09: dark mode toggle changes state
    // -------------------------------------------------------------------------

    testWidgets('dark mode toggle updates settings', (tester) async {
      AppSettings? captured;

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settings: defaultSettings,
            onSettingsChanged: (s) => captured = s,
          ),
        ),
      );

      // Toggle is initially off (isDarkMode: false)
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const Key('dark-mode-toggle')),
      );
      expect(toggle.value, isFalse);

      // Tap to enable dark mode
      await tester.tap(find.byKey(const Key('dark-mode-toggle')));
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.isDarkMode, isTrue);
    });

    // -------------------------------------------------------------------------
    // T-0448-10: API URL field accepts valid HTTPS URL
    // -------------------------------------------------------------------------

    testWidgets('API URL field accepts valid https URL', (tester) async {
      AppSettings? captured;

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settings: defaultSettings,
            onSettingsChanged: (s) => captured = s,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('api-url-field')));
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('api-url-field')),
        'https://my-nself.example.com',
      );
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.apiUrl, equals('https://my-nself.example.com'));
    });

    // -------------------------------------------------------------------------
    // T-0448-11: API URL field shows error for invalid URL
    // -------------------------------------------------------------------------

    testWidgets('API URL field shows validation error for invalid input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settings: defaultSettings,
            onSettingsChanged: (_) {},
          ),
        ),
      );

      await tester.enterText(find.byKey(const Key('api-url-field')), 'not-a-url');
      await tester.pump();

      expect(
        find.text('Please enter a valid URL (http:// or https://)'),
        findsOneWidget,
      );
    });

    // -------------------------------------------------------------------------
    // T-0448-12: Clear history button shows confirmation dialog
    // -------------------------------------------------------------------------

    testWidgets('clear history button shows confirmation dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settings: defaultSettings,
            onSettingsChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('clear-history-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('clear-history-dialog')), findsOneWidget);
      expect(find.byKey(const Key('cancel-button')), findsOneWidget);
      expect(find.byKey(const Key('confirm-clear-button')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // T-0448-13: Cancel on confirmation dialog does not call onClearHistory
    // -------------------------------------------------------------------------

    testWidgets('cancelling clear history dialog does not clear history', (tester) async {
      var cleared = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settings: defaultSettings,
            onSettingsChanged: (_) {},
            onClearHistory: () async { cleared = true; },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('clear-history-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cancel-button')));
      await tester.pumpAndSettle();

      expect(cleared, isFalse);
    });

    // -------------------------------------------------------------------------
    // T-0448-14: Confirm on dialog calls onClearHistory
    // -------------------------------------------------------------------------

    testWidgets('confirming clear history calls onClearHistory', (tester) async {
      var cleared = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settings: defaultSettings,
            onSettingsChanged: (_) {},
            onClearHistory: () async { cleared = true; },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('clear-history-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm-clear-button')));
      await tester.pumpAndSettle();

      expect(cleared, isTrue);
    });
  });
}
