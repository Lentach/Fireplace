import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fireplace/services/api_service.dart';

void main() {
  group('ApiService session / refresh contract', () {
    const base = 'http://localhost:3999';

    test('login rejects response missing refresh_token (client stays consistent)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/auth/login');
        return http.Response(
          jsonEncode({'access_token': 'only_access'}),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      });

      final api = ApiService(baseUrl: base, httpClient: mock);
      expect(
        () => api.login('user#1234', 'pass'),
        throwsA(
          predicate((e) =>
              e.toString().contains('Login response missing tokens')),
        ),
      );
    });

    test('login returns both tokens when server sends them', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'access_token': 'jwt_access',
            'refresh_token': 'opaque_refresh',
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      });

      final api = ApiService(baseUrl: base, httpClient: mock);
      final data = await api.login('user#1234', 'pass');
      expect(data['access_token'], 'jwt_access');
      expect(data['refresh_token'], 'opaque_refresh');
    });

    test('refreshSession rejects missing tokens in body', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/auth/refresh');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['refresh_token'], 'old_refresh');
        return http.Response(
          jsonEncode({'access_token': 'new_access'}),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      });

      final api = ApiService(baseUrl: base, httpClient: mock);
      expect(
        () => api.refreshSession('old_refresh'),
        throwsA(
          predicate((e) =>
              e.toString().contains('Refresh response missing tokens')),
        ),
      );
    });

    test('refreshSession returns rotated pair on success', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'access_token': 'new_access',
            'refresh_token': 'new_refresh_rotated',
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      });

      final api = ApiService(baseUrl: base, httpClient: mock);
      final data = await api.refreshSession('old_refresh');
      expect(data['access_token'], 'new_access');
      expect(data['refresh_token'], 'new_refresh_rotated');
    });

    test('refreshSession fails on 401 from server', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({'message': 'Invalid refresh token'}),
          401,
          headers: {'Content-Type': 'application/json'},
        );
      });

      final api = ApiService(baseUrl: base, httpClient: mock);
      expect(
        () => api.refreshSession('bad'),
        throwsA(
          predicate((e) =>
              e.toString().contains('Invalid refresh token')),
        ),
      );
    });
  });
}
