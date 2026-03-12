import 'dart:convert';

import 'package:http/http.dart' as http;

/// Result of a successful authentication with Hasura Auth.
class AuthResult {
  final String accessToken;
  final String? refreshToken;
  final String userId;
  final String? displayName;

  const AuthResult({
    required this.accessToken,
    this.refreshToken,
    required this.userId,
    this.displayName,
  });
}

/// Error from authentication attempt.
class AuthException implements Exception {
  final String message;
  final int? statusCode;

  const AuthException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Service for authenticating with Hasura Auth on an nSelf server.
///
/// Hasura Auth exposes sign-in at `/v1/signin/email-password` on the auth
/// subdomain, which nSelf proxies through nginx.
class AuthService {
  final http.Client _httpClient;

  AuthService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Sign in with email and password against the nSelf server's Hasura Auth.
  ///
  /// [serverUrl] is the base URL (e.g. `https://api.example.com`).
  /// Hasura Auth lives at `{serverUrl}/v1/signin/email-password`.
  Future<AuthResult> signIn({
    required String serverUrl,
    required String email,
    required String password,
  }) async {
    final url = _authUrl(serverUrl, '/v1/signin/email-password');

    final http.Response response;
    try {
      response = await _httpClient.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
    } catch (e) {
      throw AuthException(
        'Could not reach server. Check the URL and your network connection.',
      );
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final session = body['session'] as Map<String, dynamic>?;
      final user = session?['user'] as Map<String, dynamic>?;

      final accessToken = session?['accessToken'] as String?;
      if (accessToken == null) {
        throw const AuthException('Server returned success but no access token.');
      }

      return AuthResult(
        accessToken: accessToken,
        refreshToken: session?['refreshToken'] as String?,
        userId: user?['id'] as String? ?? '',
        displayName: user?['displayName'] as String?,
      );
    }

    // Parse error message from Hasura Auth response.
    String errorMsg;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      errorMsg = body['message'] as String? ?? 'Authentication failed.';
    } catch (_) {
      errorMsg = 'Authentication failed (status ${response.statusCode}).';
    }

    throw AuthException(errorMsg, statusCode: response.statusCode);
  }

  /// Build the auth endpoint URL.
  /// nSelf proxies Hasura Auth through nginx at the server's base URL.
  String _authUrl(String serverUrl, String path) {
    // Remove trailing slash from server URL.
    final base = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    return '$base$path';
  }

  void dispose() {
    _httpClient.close();
  }
}
