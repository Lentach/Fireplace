import 'dart:convert';

import 'package:fireplace/services/gif_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('GifModel', () {
    test('fromJson parses Giphy API response', () {
      final json = {
        'id': 'abc123',
        'images': {
          'fixed_height_small': {'url': 'https://media.giphy.com/small.gif'},
          'fixed_height': {'url': 'https://media.giphy.com/full.gif'},
        },
      };
      final gif = GifModel.fromJson(json);
      expect(gif.id, 'abc123');
      expect(gif.previewUrl, 'https://media.giphy.com/small.gif');
      expect(gif.fullUrl, 'https://media.giphy.com/full.gif');
    });

    test('fromJson handles genuinely ABSENT keys via null fallbacks', () {
      // Exercises the `?? {}` / `?? ''` branches — not empty strings.
      final gif = GifModel.fromJson(<String, dynamic>{});
      expect(gif.id, '');
      expect(gif.previewUrl, '');
      expect(gif.fullUrl, '');

      final noImages = GifModel.fromJson({'id': 'xyz'});
      expect(noImages.id, 'xyz');
      expect(noImages.previewUrl, '');
      expect(noImages.fullUrl, '');

      final partialImages = GifModel.fromJson({
        'id': 'xyz',
        'images': {
          'fixed_height': {'url': 'https://media.giphy.com/full.gif'},
        },
      });
      expect(partialImages.previewUrl, '');
      expect(partialImages.fullUrl, 'https://media.giphy.com/full.gif');
    });
  });

  group('GifService fetch', () {
    GifService service({
      required http.Client Function() clientFactory,
      String apiKey = 'test-key',
    }) {
      final s = GifService(clientFactory: clientFactory);
      s.apiKeyOverride = apiKey;
      return s;
    }

    test('empty api key returns [] WITHOUT any network call', () async {
      var networkCalls = 0;
      final s = service(
        apiKey: '',
        clientFactory: () => MockClient((request) async {
          networkCalls++;
          return http.Response('{}', 200);
        }),
      );

      expect(await s.fetchTrending(), isEmpty);
      expect(await s.search('cats'), isEmpty);
      expect(networkCalls, 0,
          reason: 'a keyless service must never contact Giphy');
    });

    test('non-200 response returns []', () async {
      final s = service(
        clientFactory: () =>
            MockClient((request) async => http.Response('rate limited', 429)),
      );
      expect(await s.fetchTrending(), isEmpty);
    });

    test('malformed JSON body returns []', () async {
      final s = service(
        clientFactory: () =>
            MockClient((request) async => http.Response('<html>oops', 200)),
      );
      expect(await s.fetchTrending(), isEmpty);
    });

    test('happy path parses results and sends key/query params', () async {
      late Uri captured;
      final s = service(
        clientFactory: () => MockClient((request) async {
          captured = request.url;
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'abc123',
                  'images': {
                    'fixed_height_small': {
                      'url': 'https://media.giphy.com/small.gif',
                    },
                    'fixed_height': {
                      'url': 'https://media.giphy.com/full.gif',
                    },
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final results = await s.search('cats', limit: 5);
      expect(results, hasLength(1));
      expect(results.single.id, 'abc123');
      expect(results.single.fullUrl, 'https://media.giphy.com/full.gif');
      expect(captured.queryParameters['api_key'], 'test-key');
      expect(captured.queryParameters['q'], 'cats');
      expect(captured.queryParameters['limit'], '5');
    });
  });
}
