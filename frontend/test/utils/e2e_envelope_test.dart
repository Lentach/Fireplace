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
  });
}
