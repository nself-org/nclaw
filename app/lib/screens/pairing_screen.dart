import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/server_config.dart';
import '../providers/connection_provider.dart';
import '../services/auth_service.dart';

/// Screen for pairing with a self-hosted nSelf server running the nself-claw plugin.
///
/// Flow: enter server URL + email + password -> POST to Hasura Auth ->
/// store JWT in secure storage -> navigate to home.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _urlController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  bool _pairing = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _urlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _authService.dispose();
    super.dispose();
  }

  Future<void> _handlePair() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _pairing = true;
      _errorMessage = null;
    });

    final serverUrl = _urlController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final serverName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : Uri.parse(serverUrl).host;

    try {
      final result = await _authService.signIn(
        serverUrl: serverUrl,
        email: email,
        password: password,
      );

      // Generate a stable ID from the server URL + user ID.
      final serverId =
          '${Uri.parse(serverUrl).host}_${result.userId}'.hashCode.toRadixString(16);

      final server = ServerConfig(
        id: serverId,
        url: serverUrl,
        name: serverName,
        jwtToken: result.accessToken,
        refreshToken: result.refreshToken,
      );

      await ref.read(connectionProvider.notifier).addServer(server);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Connection failed. Check the server URL.');
      }
    } finally {
      if (mounted) {
        setState(() => _pairing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Center(
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.link,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Pair with your server',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the URL of your nSelf server running the nself-claw plugin, then sign in.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Server URL field.
                    TextFormField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Server URL',
                        hintText: 'https://api.example.com',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.dns),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Server URL is required';
                        }
                        final uri = Uri.tryParse(value.trim());
                        if (uri == null ||
                            !uri.hasScheme ||
                            !uri.hasAuthority) {
                          return 'Enter a valid URL (e.g. https://api.example.com)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Server name field (optional).
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Server name (optional)',
                        hintText: 'My Server',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.label_outline),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Email field.
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Email is required';
                        }
                        if (!value.contains('@')) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password field.
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handlePair(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),

                    // Error message.
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.error
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Connect button.
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _pairing ? null : _handlePair,
                        child: _pairing
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Text('Connect'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
