import 'dart:async';
import 'dart:convert';

import 'package:fireplace/main.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/screens/auth_screen.dart';
import 'package:fireplace/services/api_service.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _expiredAccessJwt =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOjEsInVzZXJuYW1lIjoidGVzdCIsInRhZyI6IjAwMDAiLCJleHAiOjE1MTYyMzkwMjJ9.4Adcj3UFYzPUBaY63_UWOshvRZQZjm7uI9uWGQ8RrXc';

const _validAccessJwt =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOjEsInVzZXJuYW1lIjoidGVzdCIsInRhZyI6IjAwMDAiLCJleHAiOjk5OTk5OTk5OTl9.abc';

void main() {
  testWidgets('AuthGate hides login while a saved session is restoring', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'jwt_token': _expiredAccessJwt,
      'refresh_token': 'opaque_refresh',
    });
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    final mock = MockClient((request) async {
      if (request.url.path == '/auth/refresh') {
        refreshStarted.complete();
        await releaseRefresh.future;
        return http.Response(
          jsonEncode({
            'access_token': _validAccessJwt,
            'refresh_token': 'opaque_refresh',
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      }
      return http.Response('unexpected ${request.url.path}', 500);
    });
    final auth = AuthProvider(
      api: ApiService(baseUrl: 'http://localhost:3999', httpClient: mock),
    );

    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ],
        child: MaterialApp(
          theme: RpgTheme.themeDataLight,
          home: const AuthGate(),
        ),
      ),
    );
    await refreshStarted.future;
    await tester.pump();

    expect(auth.isRestoringSession, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(AuthScreen), findsNothing);

    // Keep the refresh pending: the assertion is the boot/restoring frame before
    // auth resolution, which used to show the login screen.
  });
}
