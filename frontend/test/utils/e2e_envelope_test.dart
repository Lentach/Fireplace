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

    test('build omits messageType for TEXT and includes it otherwise', () {
      final text = E2eEnvelope.build('hi');
      expect(text.containsKey('messageType'), isFalse,
          reason: 'TEXT is the wire default and must be elided');

      final voice = E2eEnvelope.build('', messageType: 'VOICE');
      expect(voice['messageType'], 'VOICE');
    });

    test('parse defaults messageType to TEXT when absent', () {
      final result = E2eEnvelope.parse(jsonEncode({'content': 'hi'}));
      expect(result.messageType, 'TEXT');
    });

    test('parse rounds a fractional num mediaDuration', () {
      final result = E2eEnvelope.parse(jsonEncode({
        'content': '',
        'messageType': 'VOICE',
        'mediaDuration': 7.6,
      }));
      expect(result.mediaDuration, 8);
    });

    test('linkPreview fields survive a build -> parse round trip', () {
      final built = E2eEnvelope.build(
        'check this out https://example.com',
        linkPreview: {
          'url': 'https://example.com',
          'title': 'Example',
          'imageUrl': 'https://example.com/og.png',
        },
      );
      final result = E2eEnvelope.parse(jsonEncode(built));
      expect(result.linkPreviewUrl, 'https://example.com');
      expect(result.linkPreviewTitle, 'Example');
      expect(result.linkPreviewImageUrl, 'https://example.com/og.png');
    });

    test('parse leaves linkPreview fields null when envelope has none', () {
      final result = E2eEnvelope.parse(jsonEncode({'content': 'hi'}));
      expect(result.linkPreviewUrl, isNull);
      expect(result.linkPreviewTitle, isNull);
      expect(result.linkPreviewImageUrl, isNull);
    });
  });
}
