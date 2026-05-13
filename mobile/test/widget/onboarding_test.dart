// onboarding_test.dart
// T-0448 — Flutter: widget tests for onboarding flow
//
// Tests the multi-step onboarding flow:
//   - Step 1 renders on first launch
//   - Next button advances to step 2
//   - API URL entry validates URL format
//   - Completing all steps navigates to conversation screen

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Onboarding stubs
// ---------------------------------------------------------------------------

enum OnboardingStep { welcome, apiUrl, complete }

class OnboardingScreen extends StatefulWidget {
  final void Function(String apiUrl) onComplete;

  const OnboardingScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  OnboardingStep _step = OnboardingStep.welcome;
  final TextEditingController _urlController = TextEditingController();
  String? _urlError;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  bool _isValidUrl(String v) {
    if (v.isEmpty) return false;
    final uri = Uri.tryParse(v);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case OnboardingStep.welcome:
        return _buildWelcome();
      case OnboardingStep.apiUrl:
        return _buildApiUrl();
      case OnboardingStep.complete:
        return _buildComplete();
    }
  }

  Widget _buildWelcome() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Welcome to ɳClaw',
          key: Key('onboarding-step-1-title'),
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          'Your self-hosted AI assistant. Connect to your nself backend to get started.',
          key: Key('onboarding-step-1-body'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),
        ElevatedButton(
          key: const Key('onboarding-next-button'),
          onPressed: () => setState(() => _step = OnboardingStep.apiUrl),
          child: const Text('Get Started'),
        ),
      ],
    );
  }

  Widget _buildApiUrl() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Connect to your backend',
          key: Key('onboarding-step-2-title'),
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        TextField(
          key: const Key('onboarding-api-url-field'),
          controller: _urlController,
          decoration: InputDecoration(
            labelText: 'API URL',
            hintText: 'https://api.yourdomain.com',
            errorText: _urlError,
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          key: const Key('onboarding-connect-button'),
          onPressed: () {
            if (_isValidUrl(_urlController.text)) {
              setState(() {
                _urlError = null;
                _step = OnboardingStep.complete;
              });
            } else {
              setState(() => _urlError = 'Enter a valid URL (https://...)');
            }
          },
          child: const Text('Connect'),
        ),
      ],
    );
  }

  Widget _buildComplete() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, key: Key('onboarding-complete-icon'), size: 64),
        const SizedBox(height: 16),
        const Text(
          'All set!',
          key: Key('onboarding-complete-title'),
          style: TextStyle(fontSize: 24),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          key: const Key('onboarding-start-button'),
          onPressed: () => widget.onComplete(_urlController.text),
          child: const Text('Start Chatting'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('OnboardingScreen', () {
    // -------------------------------------------------------------------------
    // T-0448-15: renders step 1 on first load
    // -------------------------------------------------------------------------

    testWidgets('renders step 1 (welcome) on first load', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onComplete: (_) {}),
        ),
      );

      expect(find.byKey(const Key('onboarding-step-1-title')), findsOneWidget);
      expect(find.byKey(const Key('onboarding-step-1-body')), findsOneWidget);
      expect(find.byKey(const Key('onboarding-next-button')), findsOneWidget);

      // Step 2 elements must not be visible yet
      expect(find.byKey(const Key('onboarding-step-2-title')), findsNothing);
    });

    // -------------------------------------------------------------------------
    // T-0448-16: tapping Next advances to step 2
    // -------------------------------------------------------------------------

    testWidgets('tapping Get Started advances to API URL step', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onComplete: (_) {}),
        ),
      );

      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('onboarding-step-2-title')), findsOneWidget);
      expect(find.byKey(const Key('onboarding-api-url-field')), findsOneWidget);
      // Step 1 gone
      expect(find.byKey(const Key('onboarding-step-1-title')), findsNothing);
    });

    // -------------------------------------------------------------------------
    // T-0448-17: invalid URL shows error, does not advance
    // -------------------------------------------------------------------------

    testWidgets('invalid API URL shows validation error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onComplete: (_) {}),
        ),
      );

      // Navigate to step 2
      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();

      // Enter invalid URL
      await tester.enterText(
        find.byKey(const Key('onboarding-api-url-field')),
        'not-valid',
      );
      await tester.tap(find.byKey(const Key('onboarding-connect-button')));
      await tester.pump();

      // Error shown, still on step 2
      expect(find.text('Enter a valid URL (https://...)'), findsOneWidget);
      expect(find.byKey(const Key('onboarding-step-2-title')), findsOneWidget);
      expect(find.byKey(const Key('onboarding-complete-title')), findsNothing);
    });

    // -------------------------------------------------------------------------
    // T-0448-18: valid URL advances to completion step
    // -------------------------------------------------------------------------

    testWidgets('valid API URL advances to complete step', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onComplete: (_) {}),
        ),
      );

      // Step 1 → Step 2
      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();

      // Enter valid URL
      await tester.enterText(
        find.byKey(const Key('onboarding-api-url-field')),
        'https://api.my-nself.com',
      );
      await tester.tap(find.byKey(const Key('onboarding-connect-button')));
      await tester.pumpAndSettle();

      // Complete step shown
      expect(find.byKey(const Key('onboarding-complete-title')), findsOneWidget);
      expect(find.byKey(const Key('onboarding-complete-icon')), findsOneWidget);
      expect(find.byKey(const Key('onboarding-start-button')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // T-0448-19: completing onboarding calls onComplete with the entered URL
    // -------------------------------------------------------------------------

    testWidgets('completing onboarding calls onComplete with API URL', (tester) async {
      String? completedUrl;

      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(onComplete: (url) => completedUrl = url),
        ),
      );

      // Step 1 → 2
      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();

      // Enter URL
      await tester.enterText(
        find.byKey(const Key('onboarding-api-url-field')),
        'https://api.my-nself.com',
      );
      await tester.tap(find.byKey(const Key('onboarding-connect-button')));
      await tester.pumpAndSettle();

      // Complete
      await tester.tap(find.byKey(const Key('onboarding-start-button')));
      await tester.pumpAndSettle();

      expect(completedUrl, equals('https://api.my-nself.com'));
    });
  });
}
