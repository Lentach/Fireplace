import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/constants/app_constants.dart';
import 'package:fireplace/utils/e2e_envelope.dart';
import 'package:fireplace/utils/message_length.dart';

void main() {
  int envelopeBytes(String s) =>
      utf8.encode(jsonEncode(E2eEnvelope.build(s))).length;

  group('isMessageWithinByteLimit', () {
    test('short ASCII is within limit', () {
      expect(isMessageWithinByteLimit('Hello, world!'), isTrue);
    });

    test('accepts a large but valid ASCII message', () {
      final s = 'a' * 40000;
      expect(envelopeBytes(s) <= AppConstants.maxEnvelopeBytes, isTrue);
      expect(isMessageWithinByteLimit(s), isTrue);
    });

    test('rejects an oversized ASCII message', () {
      expect(isMessageWithinByteLimit('a' * 60000), isFalse);
    });

    test('gates multi-byte emoji by bytes, not character count', () {
      // 12000 4-byte emoji ≈ 48 KB UTF-8 but far fewer UTF-16 units, so a naive
      // char/length check would wrongly pass it.
      final s = '\u{1F600}' * 12000;
      expect(s.length < AppConstants.maxEnvelopeBytes, isTrue);
      expect(
        isMessageWithinByteLimit(s),
        isFalse,
        reason: 'byte size, not char count, must gate emoji',
      );
    });

    test('measures escape-heavy content after JSON encoding', () {
      // Quotes double under JSON escaping; a raw-length check (30000) would pass,
      // but the encoded envelope is ~60 KB → must be rejected.
      final s = '"' * 30000;
      expect(s.length <= AppConstants.maxEnvelopeBytes, isTrue);
      expect(envelopeBytes(s) > AppConstants.maxEnvelopeBytes, isTrue);
      expect(isMessageWithinByteLimit(s), isFalse);
    });
  });
}
