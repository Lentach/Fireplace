import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fireplace/services/api_service.dart';

void main() {
  group('rewriteLoopbackMediaUrl', () {
    const lanBase = 'http://192.168.1.50:3000';

    test('rewrites localhost host to baseUrl host/scheme/port', () {
      expect(
        rewriteLoopbackMediaUrl(
          'http://localhost:3000/media/msgs/abc.bin',
          lanBase,
        ),
        'http://192.168.1.50:3000/media/msgs/abc.bin',
      );
    });

    test('rewrites 127.0.0.1 host too', () {
      expect(
        rewriteLoopbackMediaUrl(
          'http://127.0.0.1:3000/media/msgs/abc.bin',
          lanBase,
        ),
        'http://192.168.1.50:3000/media/msgs/abc.bin',
      );
    });

    test('rewrites to https same-origin production base', () {
      expect(
        rewriteLoopbackMediaUrl(
          'http://localhost:3000/media/msgs/voice.bin',
          'https://fireplace.example.com',
        ),
        'https://fireplace.example.com/media/msgs/voice.bin',
      );
    });

    test('leaves a non-loopback (production) host unchanged', () {
      const prod = 'https://fireplace.example.com/media/msgs/abc.bin';
      expect(rewriteLoopbackMediaUrl(prod, lanBase), prod);
    });

    test('preserves the path and query when rewriting', () {
      expect(
        rewriteLoopbackMediaUrl(
          'http://localhost:3000/media/avatars/u.jpg?v=2',
          lanBase,
        ),
        'http://192.168.1.50:3000/media/avatars/u.jpg?v=2',
      );
    });

    test('returns original url when baseUrl is malformed/empty', () {
      const url = 'http://localhost:3000/media/msgs/abc.bin';
      expect(rewriteLoopbackMediaUrl(url, ''), url);
    });
  });

  group('ApiService.fetchMediaBytes applies the loopback rewrite', () {
    test(
      'fetches the rewritten LAN host and keeps the JWT for /media/msgs/',
      () async {
        late Uri requested;
        String? authHeader;
        final mock = MockClient((request) async {
          requested = request.url;
          authHeader = request.headers['Authorization'];
          return http.Response.bytes([1, 2, 3], 200);
        });

        final api = ApiService(
          baseUrl: 'http://192.168.1.50:3000',
          httpClient: mock,
        );

        final bytes = await api.fetchMediaBytes(
          'http://localhost:3000/media/msgs/voice.bin',
          'jwt_token',
        );

        expect(requested.host, '192.168.1.50');
        expect(requested.port, 3000);
        expect(requested.path, '/media/msgs/voice.bin');
        expect(authHeader, 'Bearer jwt_token');
        expect(bytes, [1, 2, 3]);
      },
    );
  });

  // Regression for H-04: the access JWT must only ever be sent to the backend
  // origin. The media `mediaUrl` comes from the (sender-controlled, never
  // server-validated) E2E envelope, so a malicious peer could point it at an
  // attacker host containing `/media/msgs/` and harvest the recipient's token.
  group('ApiService.fetchMediaBytes restricts the JWT to the backend origin', () {
    const prodBase = 'https://fireplace.example.com';

    test('refuses to fetch an untrusted host and makes no request', () async {
      var requestMade = false;
      final mock = MockClient((request) async {
        requestMade = true;
        return http.Response.bytes([1, 2, 3], 200);
      });
      final api = ApiService(baseUrl: prodBase, httpClient: mock);

      await expectLater(
        api.fetchMediaBytes(
          'https://attacker.example/media/msgs/steal.bin',
          'jwt_token',
        ),
        throwsA(isA<Exception>()),
      );
      // The whole point: the attacker host is never contacted, so the token
      // cannot leak even in the Authorization header.
      expect(requestMade, isFalse);
    });

    test('sends the JWT for a same-origin /media/msgs/ URL', () async {
      String? authHeader;
      final mock = MockClient((request) async {
        authHeader = request.headers['Authorization'];
        return http.Response.bytes([1], 200);
      });
      final api = ApiService(baseUrl: prodBase, httpClient: mock);

      await api.fetchMediaBytes(
        '$prodBase/media/msgs/voice.bin',
        'jwt_token',
      );

      expect(authHeader, 'Bearer jwt_token');
    });

    test('fetches legacy Cloudinary media without attaching the JWT', () async {
      String? authHeader;
      Uri? requested;
      final mock = MockClient((request) async {
        requested = request.url;
        authHeader = request.headers['Authorization'];
        return http.Response.bytes([9], 200);
      });
      final api = ApiService(baseUrl: prodBase, httpClient: mock);

      final bytes = await api.fetchMediaBytes(
        'https://res.cloudinary.com/demo/image/upload/v1/x.jpg',
        'jwt_token',
      );

      expect(requested?.host, 'res.cloudinary.com');
      expect(authHeader, isNull);
      expect(bytes, [9]);
    });

    test('does NOT attach the JWT to a same-origin non-/media/msgs/ URL',
        () async {
      // Same-origin but under /media/avatars/, not /media/msgs/: the request
      // proceeds (trusted host) but the token must NOT be attached. Guards the
      // `/media/msgs/` path restriction — broadening it to all same-origin
      // paths would leak the JWT to avatar/other endpoints.
      String? authHeader;
      Uri? requested;
      final mock = MockClient((request) async {
        requested = request.url;
        authHeader = request.headers['Authorization'];
        return http.Response.bytes([7], 200);
      });
      final api = ApiService(baseUrl: prodBase, httpClient: mock);

      final bytes = await api.fetchMediaBytes(
        '$prodBase/media/avatars/u.jpg',
        'jwt_token',
      );

      expect(requested?.host, 'fireplace.example.com');
      expect(authHeader, isNull);
      expect(bytes, [7]);
    });
  });
}
