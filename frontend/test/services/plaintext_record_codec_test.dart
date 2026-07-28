import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/services/plaintext_record_codec.dart';

void main() {
  group('PlaintextRecordCodec format detection', () {
    test('a legacy cleartext record is not mistaken for a sealed one', () {
      final legacy = {'content': 'hi', '_cid': 7, '_savedAt': 123};
      expect(PlaintextRecordCodec.isSealed(legacy), isFalse);
      expect(PlaintextRecordCodec.sealedPayloadOf(legacy), isNull);
    });

    test('a sealed record is detected and its parts decode', () {
      final record = PlaintextRecordCodec.seal(
        keyId: 'k2',
        iv: Uint8List.fromList(List.filled(12, 7)),
        ciphertext: Uint8List.fromList([1, 2, 3, 4]),
        metadata: {'_cid': 7, '_savedAt': 123},
      );

      expect(PlaintextRecordCodec.isSealed(record), isTrue);
      final sealed = PlaintextRecordCodec.sealedPayloadOf(record)!;
      expect(sealed.keyId, 'k2');
      expect(sealed.iv, Uint8List.fromList(List.filled(12, 7)));
      expect(sealed.ciphertext, Uint8List.fromList([1, 2, 3, 4]));
    });

    test('a half-written envelope is refused, NOT read as cleartext', () {
      // Version but no ciphertext. Treating this as legacy would hand the
      // caller envelope scaffolding where a message should be.
      final corrupt = {'v': 1, 'kid': 'k1', '_cid': 7};
      expect(PlaintextRecordCodec.isSealed(corrupt), isFalse);
      expect(PlaintextRecordCodec.sealedPayloadOf(corrupt), isNull);
      // And its "legacy payload" must not contain envelope scaffolding.
      expect(PlaintextRecordCodec.legacyPayloadOf(corrupt), isEmpty);
    });

    test('an unknown envelope version is refused rather than guessed', () {
      final future = {
        'v': PlaintextRecordCodec.version + 1,
        'kid': 'k1',
        'iv': base64.encode(List.filled(12, 0)),
        'ct': base64.encode([9]),
      };
      expect(PlaintextRecordCodec.isSealed(future), isTrue);
      expect(
        PlaintextRecordCodec.sealedPayloadOf(future),
        isNull,
        reason: 'a newer format must not be decoded by an older reader',
      );
    });

    test('unparseable base64 is refused rather than throwing', () {
      final bad = {'v': 1, 'kid': 'k1', 'iv': 'not base64!!', 'ct': '!!'};
      expect(PlaintextRecordCodec.sealedPayloadOf(bad), isNull);
    });
  });

  group('PlaintextRecordCodec metadata split', () {
    test('metadata stays in the clear and payload excludes it', () {
      final legacy = {
        'content': 'hi',
        'mediaKey': 'mk',
        '_cid': 7,
        '_savedAt': 1,
        '_createdAt': 2,
        '_expiresAt': 3,
        '_disappearAfter': 60,
      };

      expect(PlaintextRecordCodec.metadataOf(legacy), {
        '_cid': 7,
        '_savedAt': 1,
        '_createdAt': 2,
        '_expiresAt': 3,
        '_disappearAfter': 60,
      });
      expect(PlaintextRecordCodec.legacyPayloadOf(legacy), {
        'content': 'hi',
        'mediaKey': 'mk',
      });
    });

    test('absent metadata keys are omitted, not written as null', () {
      // A null `_expiresAt` would read as "has a deadline" to a sweep that only
      // checks for the key's presence.
      final meta = PlaintextRecordCodec.metadataOf({'content': 'hi', '_cid': 7});
      expect(meta.keys, ['_cid']);
    });

    test('seal drops non-metadata keys instead of leaking them in cleartext',
        () {
      final record = PlaintextRecordCodec.seal(
        keyId: 'k1',
        iv: Uint8List(12),
        ciphertext: Uint8List.fromList([1]),
        // `content` here is a caller mistake; sealing it in the clear would
        // defeat the entire point of the envelope.
        metadata: {'_cid': 7, 'content': 'LEAK'},
      );
      expect(record.containsKey('content'), isFalse);
      expect(jsonEncode(record), isNot(contains('LEAK')));
    });
  });

  group('PlaintextRecordCodec payload round-trip', () {
    test('encode then decode preserves the payload', () {
      final payload = {'content': 'hello', 'mediaKey': 'mk', 'n': 3};
      final decoded = PlaintextRecordCodec.decodePayload(
        PlaintextRecordCodec.encodePayload(payload),
      );
      expect(decoded, payload);
    });

    test('garbage bytes decode to null, never to an empty message', () {
      final decoded = PlaintextRecordCodec.decodePayload(
        Uint8List.fromList([0xff, 0xfe, 0x00, 0x01]),
      );
      expect(
        decoded,
        isNull,
        reason: 'a wrong key must be distinguishable from a blank message',
      );
    });

    test('a JSON scalar is not accepted as a payload object', () {
      final decoded = PlaintextRecordCodec.decodePayload(
        Uint8List.fromList(utf8.encode('"just a string"')),
      );
      expect(decoded, isNull);
    });
  });
}
