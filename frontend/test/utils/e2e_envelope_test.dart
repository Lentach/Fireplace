import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/e2e_envelope.dart';

void main() {
  group('E2eEnvelope', () {
    test('build includes mediaKey and mediaIv when provided', () {
      final map = E2eEnvelope.build(
        'hello',
        mediaKey: 'key123',
        mediaIv: 'iv456',
      );
      expect(map['mediaKey'], 'key123');
      expect(map['mediaIv'], 'iv456');
    });

    test('build omits mediaKey/mediaIv when null', () {
      final map = E2eEnvelope.build('hello');
      expect(map.containsKey('mediaKey'), isFalse);
      expect(map.containsKey('mediaIv'), isFalse);
    });

    test('parse returns mediaKey and mediaIv from JSON', () {
      final json = jsonEncode({
        'content': 'hi',
        'mediaKey': 'k',
        'mediaIv': 'iv',
      });
      final result = E2eEnvelope.parse(json);
      expect(result.mediaKey, 'k');
      expect(result.mediaIv, 'iv');
    });

    test('parse returns null mediaKey for legacy envelope', () {
      final json = jsonEncode({
        'content': 'legacy',
        'mediaUrl': 'https://res.cloudinary.com/demo/image/upload/x.jpg',
      });
      final result = E2eEnvelope.parse(json);
      expect(result.mediaKey, isNull);
      expect(result.mediaIv, isNull);
    });
  });
}
