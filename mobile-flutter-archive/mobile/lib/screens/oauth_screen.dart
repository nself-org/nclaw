import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/connection_provider.dart';
import '../services/auth_service.dart';

/// OAuth WebView bridge.
/// Launched when nself-claw sends oauth_reauth_required.
/// The WebView handles the OAuth flow and intercepts the redirect URI
/// to extract the authorization code, then sends it back to nself-claw.
class OAuthScreen extends ConsumerStatefulWidget {
  final String authUrl;
  final String redirectUri;
  final String service; // 'google', 'anthropic', etc.
  final String? sessionId;

  const OAuthScreen({
    super.key,
    required this.authUrl,
    required this.redirectUri,
    required this.service,
    this.sessionId,
  });

  @override
  ConsumerState<OAuthScreen> createState() => _OAuthScreenState();
}

class _OAuthScreenState extends ConsumerState<OAuthScreen> {
  late WebViewController _controller;
  bool _completed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigation,
          onPageFinished: (_) {},
          onWebResourceError: (err) {
            setState(() => _error = err.description);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;

    // Intercept the redirect URI to extract the auth code
    if (request.url.startsWith(widget.redirectUri)) {
      final code = uri.queryParameters['code'];
      final error = uri.queryParameters['error'];

      if (error != null) {
        _completeAuth(null, error);
      } else if (code != null) {
        _completeAuth(code, null);
      }
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _completeAuth(String? code, String? error) async {
    if (_completed) return;
    setState(() => _completed = true);

    if (code != null) {
      try {
        final server = ref.read(connectionProvider).activeServer;
        if (server != null) {
          await AuthService.submitOAuthCode(
            serverUrl: server.url,
            service: widget.service,
            code: code,
            sessionId: widget.sessionId,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${_serviceName(widget.service)} connected successfully'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.of(context).pop(true); // success
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to complete auth: $e'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.of(context).pop(false); // failure
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Authorization cancelled: ${error ?? "unknown error"}'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.of(context).pop(false);
      }
    }
  }

  String _serviceName(String service) {
    switch (service) {
      case 'google':
        return 'Google';
      case 'anthropic':
        return 'Anthropic';
      case 'openai':
        return 'OpenAI';
      default:
        return service;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Connect ${_serviceName(widget.service)}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: $_error'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _controller.reload(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _completed
              ? const Center(child: CircularProgressIndicator())
              : WebViewWidget(controller: _controller),
    );
  }
}
