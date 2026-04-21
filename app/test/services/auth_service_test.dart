// Unit tests for AuthService using http MockClient.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:nself_claw/services/auth_service.dart';

void main() {
  group('AuthService.signIn', () {
    test('returns AuthResult on 200 with full session', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://api.example.com/v1/signin/email-password',
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['email'], 'a@b.com');
        expect(body['password'], 'secret');
        return http.Response(
          jsonEncode({
            'session': {
              'accessToken': 'jwt-123',
              'refreshToken': 'r-456',
              'user': {'id': 'u1', 'displayName': 'Ada'},
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final svc = AuthService(httpClient: client);
      final res = await svc.signIn(
        serverUrl: 'https://api.example.com',
        email: 'a@b.com',
        password: 'secret',
      );
      expect(res.accessToken, 'jwt-123');
      expect(res.refreshToken, 'r-456');
      expect(res.userId, 'u1');
      expect(res.displayName, 'Ada');
    });

    test('strips trailing slash from serverUrl', () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.example.com/v1/signin/email-password',
        );
        return http.Response(
          jsonEncode({
            'session': {
              'accessToken': 'jwt',
              'user': {'id': 'u1'},
            }
          }),
          200,
        );
      });
      final svc = AuthService(httpClient: client);
      final res = await svc.signIn(
        serverUrl: 'https://api.example.com/',
        email: 'a@b.com',
        password: 'x',
      );
      expect(res.accessToken, 'jwt');
    });

    test('throws when accessToken is missing', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode({'session': {'user': {'id': 'u'}}}), 200));
      final svc = AuthService(httpClient: client);
      expect(
        () => svc.signIn(
          serverUrl: 'https://x',
          email: 'a@b.com',
          password: 'x',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('throws AuthException with server message on non-200', () async {
      final client = MockClient(
          (_) async => http.Response(jsonEncode({'message': 'Bad creds'}), 401));
      final svc = AuthService(httpClient: client);
      try {
        await svc.signIn(
          serverUrl: 'https://x',
          email: 'a',
          password: 'b',
        );
        fail('should have thrown');
      } on AuthException catch (e) {
        expect(e.statusCode, 401);
        expect(e.message, contains('Bad creds'));
        expect(e.toString(), contains('Bad creds'));
      }
    });

    test('throws AuthException on unparseable error body', () async {
      final client = MockClient((_) async => http.Response('<html>500</html>', 500));
      final svc = AuthService(httpClient: client);
      expect(
        () => svc.signIn(
            serverUrl: 'https://x', email: 'a', password: 'b'),
        throwsA(isA<AuthException>()),
      );
    });

    test('throws AuthException when network call fails', () async {
      final client = MockClient((_) async {
        throw Exception('connection refused');
      });
      final svc = AuthService(httpClient: client);
      expect(
        () => svc.signIn(
          serverUrl: 'https://x',
          email: 'a',
          password: 'b',
        ),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('AuthService.redeemPairCode', () {
    test('returns userId on 200', () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.example.com/claw/devices/pair/redeem',
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['token'], 'ABC123'); // uppercased, trimmed
        return http.Response(jsonEncode({'user_id': 'user-42'}), 200);
      });
      final svc = AuthService(httpClient: client);
      final id = await svc.redeemPairCode(
        serverUrl: 'https://api.example.com',
        code: ' abc123 ',
      );
      expect(id, 'user-42');
    });

    test('throws when user_id missing from body', () async {
      final client = MockClient((_) async => http.Response(jsonEncode({}), 200));
      final svc = AuthService(httpClient: client);
      expect(
        () => svc.redeemPairCode(
          serverUrl: 'https://x',
          code: 'abc',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('throws with specific message on 429', () async {
      final client = MockClient(
          (_) async => http.Response(jsonEncode({'error': 'rl'}), 429));
      final svc = AuthService(httpClient: client);
      try {
        await svc.redeemPairCode(serverUrl: 'https://x', code: 'abc');
        fail('should have thrown');
      } on AuthException catch (e) {
        expect(e.statusCode, 429);
        expect(e.message, contains('Too many attempts'));
      }
    });

    test('throws with server error message on 400', () async {
      final client = MockClient(
          (_) async => http.Response(jsonEncode({'error': 'bad code'}), 400));
      final svc = AuthService(httpClient: client);
      try {
        await svc.redeemPairCode(serverUrl: 'https://x', code: 'xyz');
        fail('should have thrown');
      } on AuthException catch (e) {
        expect(e.statusCode, 400);
        expect(e.message, contains('bad code'));
      }
    });

    test('throws with fallback message on unparseable body', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      final svc = AuthService(httpClient: client);
      expect(
        () => svc.redeemPairCode(serverUrl: 'https://x', code: 'a'),
        throwsA(isA<AuthException>()),
      );
    });

    test('throws AuthException on network failure', () async {
      final client = MockClient((_) async {
        throw Exception('no route to host');
      });
      final svc = AuthService(httpClient: client);
      expect(
        () => svc.redeemPairCode(serverUrl: 'https://x', code: 'a'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('AuthException', () {
    test('toString returns the message', () {
      const e = AuthException('boom', statusCode: 500);
      expect(e.toString(), 'boom');
      expect(e.statusCode, 500);
    });
  });

  group('AuthResult', () {
    test('constructor preserves all fields', () {
      const r = AuthResult(
        accessToken: 'a',
        refreshToken: 'r',
        userId: 'u',
        displayName: 'd',
      );
      expect(r.accessToken, 'a');
      expect(r.refreshToken, 'r');
      expect(r.userId, 'u');
      expect(r.displayName, 'd');
    });

    test('refresh and display are optional', () {
      const r = AuthResult(accessToken: 'a', userId: 'u');
      expect(r.refreshToken, isNull);
      expect(r.displayName, isNull);
    });
  });

  group('AuthService.dispose', () {
    test('closes underlying http client', () {
      final client = MockClient((_) async => http.Response('', 200));
      final svc = AuthService(httpClient: client);
      expect(() => svc.dispose(), returnsNormally);
    });
  });
}
