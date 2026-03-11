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
      final envelope = E2eEnvelope.build('Check this out', linkPreview);
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
      final envelope = E2eEnvelope.build(content, linkPreview);
      final json = jsonEncode(envelope);
      final parsed = E2eEnvelope.parse(json);
      expect(parsed.content, content);
      expect(parsed.linkPreviewUrl, linkPreview['url']);
      expect(parsed.linkPreviewTitle, linkPreview['title']);
      expect(parsed.linkPreviewImageUrl, linkPreview['imageUrl']);
    });
  });
}
