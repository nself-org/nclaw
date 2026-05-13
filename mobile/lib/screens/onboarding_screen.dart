import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../providers/connection_provider.dart';

/// 7-step first-run onboarding wizard for ɳClaw.
///
/// Steps:
///   0 — Welcome
///   1 — Server resources (local model detection)
///   2 — Model install
///   3 — Google OAuth (Gemini)
///   4 — Add more accounts
///   5 — Routing summary
///   6 — Finish
///
/// When the user taps "Start Chatting" on the final step, the screen pops.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 7;

  // Step 1 — model detection
  String? _recommendedModel;
  bool _modelDetecting = false;
  String? _modelDetectError;

  // Step 2 — model install
  bool _installingModel = false;
  String? _installResult;

  // Step 4 — Gemini accounts
  int _geminiAccountCount = 0;
  bool _loadingAccounts = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String? get _serverUrl =>
      ref.read(connectionProvider).activeServer?.url;

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      final next = _currentStep + 1;
      setState(() => _currentStep = next);
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _onStepEnter(next);
    } else {
      // Final step — pop
      Navigator.of(context).pop();
    }
  }

  void _onStepEnter(int step) {
    switch (step) {
      case 1:
        _detectModels();
      case 4:
        _loadGeminiAccounts();
      default:
        break;
    }
  }

  Future<void> _detectModels() async {
    final url = _serverUrl;
    if (url == null || url.isEmpty) return;
    setState(() {
      _modelDetecting = true;
      _modelDetectError = null;
      _recommendedModel = null;
    });
    try {
      final uri = Uri.parse('$url/ai/models/local');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String? model;
        if (data is Map<String, dynamic>) {
          model = data['recommended'] as String? ??
              (data['models'] is List && (data['models'] as List).isNotEmpty
                  ? (data['models'] as List).first['name'] as String?
                  : null);
        }
        setState(() => _recommendedModel = model ?? 'llama3.2');
      } else {
        setState(() => _recommendedModel = 'llama3.2');
      }
    } catch (_) {
      setState(() {
        _recommendedModel = 'llama3.2';
        _modelDetectError = 'Could not reach server. Using default model.';
      });
    } finally {
      setState(() => _modelDetecting = false);
    }
  }

  Future<void> _installModel() async {
    final url = _serverUrl;
    if (url == null || url.isEmpty) return;
    setState(() {
      _installingModel = true;
      _installResult = null;
    });
    try {
      final uri = Uri.parse('$url/ai/models/local/install');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'auto': true}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 || response.statusCode == 202) {
        setState(() => _installResult = 'success');
      } else {
        setState(() => _installResult = 'error');
      }
    } catch (_) {
      setState(() => _installResult = 'error');
    } finally {
      setState(() => _installingModel = false);
    }
  }

  Future<void> _openGoogleOAuth() async {
    final url = _serverUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse('$url/claw/oauth/google/start');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _loadGeminiAccounts() async {
    final url = _serverUrl;
    if (url == null || url.isEmpty) return;
    setState(() => _loadingAccounts = true);
    try {
      final uri = Uri.parse('$url/ai/gemini/accounts');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        int count = 0;
        if (data is Map<String, dynamic>) {
          count = (data['count'] as int?) ??
              (data['accounts'] is List
                  ? (data['accounts'] as List).length
                  : 0);
        } else if (data is List) {
          count = data.length;
        }
        setState(() => _geminiAccountCount = count);
      }
    } catch (_) {
      // Keep count at 0 on error — non-critical.
    } finally {
      setState(() => _loadingAccounts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: step N of 7 + skip button
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Step ${_currentStep + 1} of $_totalSteps',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const Spacer(),
                  if (_currentStep < _totalSteps - 1)
                    TextButton(
                      onPressed: _nextStep,
                      child: const Text('Skip'),
                    ),
                ],
              ),
            ),
            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep0(theme),
                  _buildStep1(theme),
                  _buildStep2(theme),
                  _buildStep3(theme),
                  _buildStep4(theme),
                  _buildStep5(theme),
                  _buildStep6(theme),
                ],
              ),
            ),
            // Dots progress indicator
            _DotsIndicator(
              total: _totalSteps,
              current: _currentStep,
              activeColor: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            // Bottom action button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: _buildBottomButton(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton(ThemeData theme) {
    if (_currentStep == 2) {
      // Step 2: Install / Skip pair side by side
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _nextStep,
              child: const Text('Skip'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _installingModel ? null : _installAndNext,
              child: _installingModel
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Install'),
            ),
          ),
        ],
      );
    }
    if (_currentStep == 3) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _nextStep,
              child: const Text('Skip'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: () async {
                await _openGoogleOAuth();
                _nextStep();
              },
              child: const Text('Open Browser'),
            ),
          ),
        ],
      );
    }
    if (_currentStep == 4) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _nextStep,
              child: const Text('Continue'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: () async {
                await _openGoogleOAuth();
                await _loadGeminiAccounts();
              },
              child: const Text('Add Another'),
            ),
          ),
        ],
      );
    }
    if (_currentStep == _totalSteps - 1) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Start Chatting'),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _nextStep,
        child: Text(_currentStep == 0 ? 'Get Started' : 'Continue'),
      ),
    );
  }

  Future<void> _installAndNext() async {
    await _installModel();
    _nextStep();
  }

  // ---- Step builders ----

  Widget _buildStep0(ThemeData theme) {
    return _StepContainer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.smart_toy_outlined,
            size: 80,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 32),
          Text(
            'Welcome to \u0273Claw',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Your self-hosted AI assistant. ɳClaw routes your requests '
            'intelligently across local models, free Gemini accounts, and '
            'API keys — keeping costs low and your data on your server.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStep1(ThemeData theme) {
    return _StepContainer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.storage_outlined,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Server Resources',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_modelDetecting)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Detecting your server...'),
              ],
            )
          else if (_recommendedModel != null) ...[
            Text(
              'Recommended local model:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _recommendedModel!,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            if (_modelDetectError != null) ...[
              const SizedBox(height: 8),
              Text(
                _modelDetectError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ] else
            Text(
              'Connect to a server to detect available models.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _buildStep2(ThemeData theme) {
    final model = _recommendedModel ?? 'a local model';
    return _StepContainer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_outlined,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Install $model for free local AI?',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Local models run entirely on your server — no API costs, '
            'no data leaving your infrastructure.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          if (_installResult == 'success') ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Download started',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ] else if (_installResult == 'error') ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  'Install failed — you can retry later',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep3(ThemeData theme) {
    return _StepContainer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_circle_outlined,
            size: 64,
            color: Colors.blue.shade400,
          ),
          const SizedBox(height: 24),
          Text(
            'Link Google for free Gemini',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Connect a Google account to enable free Gemini Flash usage. '
            'Each account contributes to your free daily quota.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStep4(ThemeData theme) {
    return _StepContainer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.group_add_outlined,
            size: 64,
            color: Colors.blue.shade400,
          ),
          const SizedBox(height: 24),
          Text(
            'Add More Accounts',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_loadingAccounts)
            const CircularProgressIndicator()
          else ...[
            Text(
              _geminiAccountCount == 0
                  ? 'No Gemini accounts linked yet.'
                  : '$_geminiAccountCount Gemini ${_geminiAccountCount == 1 ? 'account' : 'accounts'} linked.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'More accounts means more free daily Gemini requests. '
            'You can always add more later.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStep5(ThemeData theme) {
    return _StepContainer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.route_outlined,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Your routing is configured',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _RoutingRow(
            icon: Icons.computer,
            color: Colors.green,
            label: 'Local model',
            description: 'Fast, free, private',
          ),
          const SizedBox(height: 12),
          _RoutingRow(
            icon: Icons.account_circle_outlined,
            color: Colors.blue,
            label: 'Free Gemini',
            description: 'Falls back when local is busy',
          ),
          const SizedBox(height: 12),
          _RoutingRow(
            icon: Icons.key_outlined,
            color: Colors.orange,
            label: 'API keys',
            description: 'Last resort — paid usage only',
          ),
          const SizedBox(height: 16),
          Text(
            'ɳClaw routes each request to the cheapest available tier automatically.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStep6(ThemeData theme) {
    return _StepContainer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.rocket_launch_outlined,
            size: 80,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 32),
          Text(
            '\u0273Claw is ready!',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Your self-hosted AI assistant is set up and ready to go.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---- Supporting widgets ----

class _StepContainer extends StatelessWidget {
  final Widget child;

  const _StepContainer({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: child,
      ),
    );
  }
}

class _DotsIndicator extends StatelessWidget {
  final int total;
  final int current;
  final Color activeColor;

  const _DotsIndicator({
    required this.total,
    required this.current,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (index) {
        final isActive = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? activeColor
                : activeColor.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _RoutingRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String description;

  const _RoutingRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
