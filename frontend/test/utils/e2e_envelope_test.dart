import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/e2e_envelope.dart';

void main() {
  group('E2eEnvelope', () {
    test('build returns content-only envelope when no linkPreview', () {
      final envelope = E2eEnvelope.build('Hello world');
      expect(envelope['content'], 'Hello world');
      expect(envelope.containsKey('linkPreview'), false);
    });

    test('build includes linkPreview when provided', () {
      final linkPreview = {
        'url': 'https://example.com',
        'title': 'Example',
        'imageUrl': 'https://example.com/thumb.png',
      };
      final envelope = E2eEnvelope.build('Check this out', linkPreview: linkPreview);
      expect(envelope['content'], 'Check this out');
      expect(envelope['linkPreview'], linkPreview);
    });

    test('parse extracts content from envelope', () {
      final json = jsonEncode({'content': 'Secret message'});
      final parsed = E2eEnvelope.parse(json);
      expect(parsed.content, 'Secret message');
      expect(parsed.linkPreviewUrl, isNull);
      expect(parsed.linkPreviewTitle, isNull);
      expect(parsed.linkPreviewImageUrl, isNull);
    });

    test('parse extracts link preview fields', () {
      final json = jsonEncode({
        'content': 'Link',
        'linkPreview': {
          'url': 'https://example.com',
          'title': 'Example Site',
          'imageUrl': 'https://example.com/og.png',
        },
      });
      final parsed = E2eEnvelope.parse(json);
      expect(parsed.content, 'Link');
      expect(parsed.linkPreviewUrl, 'https://example.com');
      expect(parsed.linkPreviewTitle, 'Example Site');
      expect(parsed.linkPreviewImageUrl, 'https://example.com/og.png');
    });

    test('parse returns empty content when missing', () {
      final json = jsonEncode({'linkPreview': {}});
      final parsed = E2eEnvelope.parse(json);
      expect(parsed.content, '');
    });

    test('build then parse round-trip', () {
      const content = 'Hello with link https://example.com';
      final linkPreview = {
        'url': 'https://example.com',
        'title': 'Example',
        'imageUrl': 'https://example.com/img.png',
      };
      final envelope = E2eEnvelope.build(content, linkPreview: linkPreview);
      final json = jsonEncode(envelope);
      final parsed = E2eEnvelope.parse(json);
      expect(parsed.content, content);
      expect(parsed.linkPreviewUrl, linkPreview['url']);
      expect(parsed.linkPreviewTitle, linkPreview['title']);
      expect(parsed.linkPreviewImageUrl, linkPreview['imageUrl']);
    });

    test('build includes messageType when provided', () {
      final envelope = E2eEnvelope.build('', messageType: 'PING');
      expect(envelope['messageType'], 'PING');
    });

    test('build includes mediaUrl and mediaDuration', () {
      final envelope = E2eEnvelope.build('', messageType: 'VOICE', mediaUrl: 'https://example.com/audio.m4a', mediaDuration: 5);
      expect(envelope['messageType'], 'VOICE');
      expect(envelope['mediaUrl'], 'https://example.com/audio.m4a');
      expect(envelope['mediaDuration'], 5);
    });

    test('parse returns messageType TEXT when absent (backward compat)', () {
      final json = '{"content":"hello"}';
      final parsed = E2eEnvelope.parse(json);
      expect(parsed.messageType, 'TEXT');
    });

    test('parse extracts messageType, mediaUrl, mediaDuration', () {
      final json = '{"content":"","messageType":"VOICE","mediaUrl":"https://example.com/a.m4a","mediaDuration":10}';
      final parsed = E2eEnvelope.parse(json);
      expect(parsed.messageType, 'VOICE');
      expect(parsed.mediaUrl, 'https://example.com/a.m4a');
      expect(parsed.mediaDuration, 10);
    });

    test('build then parse round-trip with all fields', () {
      final envelope = E2eEnvelope.build('hello', messageType: 'IMAGE', mediaUrl: 'https://img.com/1.jpg');
      final json = jsonEncode(envelope);
      final parsed = E2eEnvelope.parse(json);
      expect(parsed.content, 'hello');
      expect(parsed.messageType, 'IMAGE');
      expect(parsed.mediaUrl, 'https://img.com/1.jpg');
      expect(parsed.mediaDuration, isNull);
    });

    // --- E2E all message types: full round-trip tests ---

    group('E2E all message types round-trip', () {
      test('PING: empty content, messageType preserved, no media', () {
        final envelope = E2eEnvelope.build('', messageType: 'PING');
        final json = jsonEncode(envelope);
        final parsed = E2eEnvelope.parse(json);

        expect(parsed.content, '');
        expect(parsed.messageType, 'PING');
        expect(parsed.mediaUrl, isNull);
        expect(parsed.mediaDuration, isNull);
        expect(parsed.linkPreviewUrl, isNull);
      });

      test('VOICE: empty content, Cloudinary mediaUrl + duration preserved', () {
        const url = 'https://res.cloudinary.com/demo/video/upload/v1/voice/abc.m4a';
        final envelope = E2eEnvelope.build('', messageType: 'VOICE', mediaUrl: url, mediaDuration: 12);
        final json = jsonEncode(envelope);
        final parsed = E2eEnvelope.parse(json);

        expect(parsed.content, '');
        expect(parsed.messageType, 'VOICE');
        expect(parsed.mediaUrl, url);
        expect(parsed.mediaDuration, 12);
        expect(parsed.linkPreviewUrl, isNull);
      });

      test('IMAGE: Cloudinary mediaUrl preserved, no duration', () {
        const url = 'https://res.cloudinary.com/demo/image/upload/v1/images/photo.jpg';
        final envelope = E2eEnvelope.build('', messageType: 'IMAGE', mediaUrl: url);
        final json = jsonEncode(envelope);
        final parsed = E2eEnvelope.parse(json);

        expect(parsed.content, '');
        expect(parsed.messageType, 'IMAGE');
        expect(parsed.mediaUrl, url);
        expect(parsed.mediaDuration, isNull);
      });

      test('TEXT with link preview: all preview fields preserved', () {
        final lp = {
          'url': 'https://github.com',
          'title': 'GitHub',
          'imageUrl': 'https://github.com/og.png',
        };
        final envelope = E2eEnvelope.build('Check https://github.com', linkPreview: lp);
        final json = jsonEncode(envelope);
        final parsed = E2eEnvelope.parse(json);

        expect(parsed.content, 'Check https://github.com');
        expect(parsed.messageType, 'TEXT');
        expect(parsed.linkPreviewUrl, 'https://github.com');
        expect(parsed.linkPreviewTitle, 'GitHub');
        expect(parsed.linkPreviewImageUrl, 'https://github.com/og.png');
      });

      test('TEXT with partial link preview (no imageUrl)', () {
        final lp = <String, String?>{
          'url': 'https://example.com',
          'title': 'Example',
          'imageUrl': null,
        };
        final envelope = E2eEnvelope.build('link here', linkPreview: lp);
        final json = jsonEncode(envelope);
        final parsed = E2eEnvelope.parse(json);

        expect(parsed.linkPreviewUrl, 'https://example.com');
        expect(parsed.linkPreviewTitle, 'Example');
        expect(parsed.linkPreviewImageUrl, isNull);
      });
    });

    group('E2E envelope edge cases', () {
      test('TEXT omits messageType key (compact envelope)', () {
        final envelope = E2eEnvelope.build('hello');
        expect(envelope.containsKey('messageType'), false,
            reason: 'TEXT is default, should be omitted for compact envelope');
        expect(envelope.containsKey('mediaUrl'), false);
        expect(envelope.containsKey('mediaDuration'), false);
      });

      test('non-TEXT always includes messageType key', () {
        for (final type in ['PING', 'VOICE', 'IMAGE']) {
          final envelope = E2eEnvelope.build('', messageType: type);
          expect(envelope['messageType'], type,
              reason: '$type must be explicitly stored in envelope');
        }
      });

      test('parse with unknown messageType returns it as-is', () {
        final json = '{"content":"x","messageType":"FUTURE_TYPE"}';
        final parsed = E2eEnvelope.parse(json);
        expect(parsed.messageType, 'FUTURE_TYPE');
      });

      test('parse malformed JSON throws', () {
        expect(() => E2eEnvelope.parse('not json'), throwsFormatException);
      });

      test('VOICE with zero duration', () {
        final envelope = E2eEnvelope.build('', messageType: 'VOICE', mediaUrl: 'https://x.com/a.m4a', mediaDuration: 0);
        // 0 is falsy for int but should still be preserved if explicitly set
        // Current impl: mediaDuration != null check — 0 passes
        final json = jsonEncode(envelope);
        final parsed = E2eEnvelope.parse(json);
        expect(parsed.mediaDuration, 0);
      });

      test('all fields combined in single envelope', () {
        final envelope = E2eEnvelope.build(
          'voice with link?',
          messageType: 'VOICE',
          mediaUrl: 'https://res.cloudinary.com/x/video/upload/v1/a.m4a',
          mediaDuration: 30,
          linkPreview: {'url': 'https://a.com', 'title': 'A', 'imageUrl': 'https://a.com/i.png'},
        );
        final json = jsonEncode(envelope);
        final parsed = E2eEnvelope.parse(json);

        expect(parsed.content, 'voice with link?');
        expect(parsed.messageType, 'VOICE');
        expect(parsed.mediaUrl, 'https://res.cloudinary.com/x/video/upload/v1/a.m4a');
        expect(parsed.mediaDuration, 30);
        expect(parsed.linkPreviewUrl, 'https://a.com');
        expect(parsed.linkPreviewTitle, 'A');
        expect(parsed.linkPreviewImageUrl, 'https://a.com/i.png');
      });
    });
  });
}
