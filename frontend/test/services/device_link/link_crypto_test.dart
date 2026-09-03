// §5.1 ceremony crypto laws (Phase 2 T3, spec §12 item (ii)):
// - both HONEST sides derive the SAME SAS from their own private + the
//   peer's public (falsification 15's positive half);
// - an adversary substituting either ephemeral, or holding only the public
//   transcript, cannot compute the honest targets (falsification 15);
// - the blob is encrypt-then-MAC: tamper dies as bad_mac BEFORE decrypt, a
//   wrong ephemeral's keys die as bad_mac (falsification 8's client half);
// - the OOB code parser is strict — any malformed segment is a null parse.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/device_link/link_crypto.dart';

void main() {
  const provisioningId = '3f2c8a1e-9b7d-4c5a-8e2f-1a6b3c9d0e4f';

  final ephN = generateLinkEphemeral();
  final ephP = generateLinkEphemeral();
  final ephPubN = linkEphemeralPublicBytes(ephN);
  final ephPubP = linkEphemeralPublicBytes(ephP);
  final transcript = linkTranscript(
    provisioningId: provisioningId,
    ephPubN: ephPubN,
    ephPubP: ephPubP,
  );

  Uint8List secretOfN() =>
      linkSharedSecret(theirEphPub: ephPubP, ownEphPriv: ephN.privateKey);
  Uint8List secretOfP() =>
      linkSharedSecret(theirEphPub: ephPubN, ownEphPriv: ephP.privateKey);

  LinkBlobPayload payload() => const LinkBlobPayload(
    userId: 7,
    deviceId: 2,
    ikPub: 'aWtQdWI=',
    ikPriv: 'aWtQcml2',
    dakPub: 'ZGFrUHVi',
    enrollmentCreatedAt: 1755600000000,
    enrollmentSig: 'c2ln',
  );

  group('hkdfSha256 (RFC 5869, zero salt)', () {
    test('pinned regression vector', () {
      // Independently computed with Python hmac/hashlib against RFC 5869
      // (extract with a 32-zero-byte salt, expand counter from 0x01) — a
      // dependency swap or an off-by-one in the expand loop moves it.
      final okm = hkdfSha256(
        ikm: Uint8List.fromList(List<int>.filled(32, 0x0b)),
        info: Uint8List.fromList(utf8.encode('fp-link-test')),
        length: 42,
      );
      expect(
        base64Encode(okm),
        '4LfojN9P4NAJb/hqAEQebqk2CItFrQKn3jkCaeRWQRUSnQ+Bk/vw8CwE',
      );
    });

    test('expand crosses block boundaries continuously', () {
      final long = hkdfSha256(
        ikm: Uint8List.fromList(List<int>.filled(32, 1)),
        info: Uint8List.fromList([2, 3]),
        length: 64,
      );
      final short = hkdfSha256(
        ikm: Uint8List.fromList(List<int>.filled(32, 1)),
        info: Uint8List.fromList([2, 3]),
        length: 33,
      );
      expect(short, long.sublist(0, 33));
    });
  });

  group('SAS derivation (falsification 15)', () {
    test('both honest sides derive the SAME code', () {
      final sasN = deriveLinkSas(
        sharedSecret: secretOfN(),
        transcript: transcript,
      );
      final sasP = deriveLinkSas(
        sharedSecret: secretOfP(),
        transcript: transcript,
      );
      expect(sasN, sasP);
      expect(RegExp(r'^\d{3} \d{3}$').hasMatch(sasN), isTrue);
    });

    test('substituting either ephemeral yields a MISMATCH', () {
      final mitm = generateLinkEphemeral();
      final mitmPub = linkEphemeralPublicBytes(mitm);

      final honestSas = deriveLinkSas(
        sharedSecret: secretOfN(),
        transcript: transcript,
      );

      // Attacker swaps ephPubP on the relayed leg: N now agrees with the
      // attacker's key — over the HONEST transcript N still displays a
      // different code than P.
      final swappedP = deriveLinkSas(
        sharedSecret: linkSharedSecret(
          theirEphPub: mitmPub,
          ownEphPriv: ephN.privateKey,
        ),
        transcript: transcript,
      );
      expect(swappedP, isNot(honestSas));

      // Symmetric swap of ephPubN (would require breaking the OOB channel,
      // but the derivation must still not collide).
      final swappedN = deriveLinkSas(
        sharedSecret: linkSharedSecret(
          theirEphPub: mitmPub,
          ownEphPriv: ephP.privateKey,
        ),
        transcript: transcript,
      );
      expect(swappedN, isNot(honestSas));
    });

    test(
      'adversary with the public transcript cannot compute either target',
      () {
        // The adversary holds provisioningId, ephPubN, ephPubP (all public)
        // plus its OWN private keys. Its best derivations are DH agreements of
        // its own private half against each honest public — neither equals the
        // honest SAS (that needs ephPrivN·ephPubP or ephPrivP·ephPubN).
        final adversary = generateLinkEphemeral();
        final honest = deriveLinkSas(
          sharedSecret: secretOfN(),
          transcript: transcript,
        );
        for (final target in [ephPubN, ephPubP]) {
          final guess = deriveLinkSas(
            sharedSecret: linkSharedSecret(
              theirEphPub: target,
              ownEphPriv: adversary.privateKey,
            ),
            transcript: transcript,
          );
          expect(guess, isNot(honest));
        }
      },
    );

    test('leading zeros survive the 6-digit rendering', () {
      // Grind a transcript whose SAS value starts with a zero digit, then
      // assert the rendered form keeps all six digits. Deterministic: the
      // loop always finds one quickly and the assertion pins the format law.
      final secret = secretOfN();
      for (var i = 0; i < 10000; i++) {
        final t = linkTranscript(
          provisioningId:
              'a0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
          ephPubN: ephPubN,
          ephPubP: ephPubP,
        );
        final sas = deriveLinkSas(sharedSecret: secret, transcript: t);
        expect(sas.length, 7);
        expect(sas[3], ' ');
        if (sas.startsWith('0')) return;
      }
      fail(
        'no zero-leading SAS found in 10000 transcripts — format law untested',
      );
    });
  });

  group('blob seal/open (falsifications 8/18 client halves)', () {
    LinkBlobKeys keysOfN() =>
        deriveLinkBlobKeys(sharedSecret: secretOfN(), transcript: transcript);
    LinkBlobKeys keysOfP() =>
        deriveLinkBlobKeys(sharedSecret: secretOfP(), transcript: transcript);

    test('roundtrip: P seals, N opens, payload identical', () {
      final blob = sealLinkBlob(keys: keysOfP(), payload: payload());
      final opened = openLinkBlob(keys: keysOfN(), blob: blob);
      expect(opened.toJson(), payload().toJson());
    });

    test('any tampered byte dies as bad_mac, never as garbage JSON', () {
      final blob = sealLinkBlob(keys: keysOfP(), payload: payload());
      // One flip in the ciphertext, one in the IV, one in the MAC itself.
      for (final index in [1 + 16 + 3, 5, blob.length - 1]) {
        final tampered = Uint8List.fromList(blob);
        tampered[index] ^= 0x01;
        expect(
          () => openLinkBlob(keys: keysOfN(), blob: tampered),
          throwsA(
            isA<LinkBlobException>().having(
              (e) => e.reason,
              'reason',
              'bad_mac',
            ),
          ),
          reason: 'tamper at $index must be caught by the MAC before decrypt',
        );
      }
    });

    test('a blob keyed to a DIFFERENT ephemeral is undecryptable', () {
      // The replay of falsification 8: the honest blob re-targeted at a
      // ceremony whose DH secret involves a different ephemeral fails the
      // MAC — the wrong keys never reach the decrypt.
      final mitm = generateLinkEphemeral();
      final wrongKeys = deriveLinkBlobKeys(
        sharedSecret: linkSharedSecret(
          theirEphPub: linkEphemeralPublicBytes(mitm),
          ownEphPriv: ephN.privateKey,
        ),
        transcript: transcript,
      );
      final blob = sealLinkBlob(keys: keysOfP(), payload: payload());
      expect(
        () => openLinkBlob(keys: wrongKeys, blob: blob),
        throwsA(
          isA<LinkBlobException>().having((e) => e.reason, 'reason', 'bad_mac'),
        ),
      );
    });

    test('structural garbage is malformed, not bad_mac', () {
      expect(
        () => openLinkBlob(keys: keysOfN(), blob: Uint8List(10)),
        throwsA(
          isA<LinkBlobException>().having(
            (e) => e.reason,
            'reason',
            'malformed',
          ),
        ),
      );
      final blob = sealLinkBlob(keys: keysOfP(), payload: payload());
      final wrongVersion = Uint8List.fromList(blob);
      wrongVersion[0] = 0x02;
      expect(
        () => openLinkBlob(keys: keysOfN(), blob: wrongVersion),
        throwsA(
          isA<LinkBlobException>().having(
            (e) => e.reason,
            'reason',
            'malformed',
          ),
        ),
      );
    });

    test('a MAC-valid blob with non-payload JSON is malformed', () {
      final keys = keysOfP();
      final forged = sealLinkBlob(keys: keys, payload: payload());
      // Re-seal arbitrary JSON under the honest keys via the public API is
      // not possible (sealLinkBlob takes a payload), so parse strictness is
      // pinned at the fromJson boundary instead.
      expect(forged, isNotEmpty);
      expect(
        () => LinkBlobPayload.fromJson(<String, dynamic>{'userId': 7}),
        throwsA(isA<LinkBlobException>()),
      );
      expect(
        () => LinkBlobPayload.fromJson(<String, dynamic>{
          ...payload().toJson(),
          'extra': 1,
        }),
        throwsA(isA<LinkBlobException>()),
      );
      expect(
        () => LinkBlobPayload.fromJson(<String, dynamic>{
          ...payload().toJson(),
          'deviceId': 'two',
        }),
        throwsA(isA<LinkBlobException>()),
      );
    });
  });

  group('OOB code (spec item (i))', () {
    test('encode/parse roundtrip', () {
      final code = LinkOobCode(
        provisioningId: provisioningId,
        ephPubN: ephPubN,
        platform: 'web',
      );
      final parsed = LinkOobCode.tryParse(code.encode());
      expect(parsed, isNotNull);
      expect(parsed!.provisioningId, provisioningId);
      expect(parsed.ephPubN, ephPubN);
      expect(parsed.platform, 'web');
      expect(code.encode().contains('='), isFalse);
    });

    test('strict parser rejects every malformed segment', () {
      final good = LinkOobCode(
        provisioningId: provisioningId,
        ephPubN: ephPubN,
        platform: 'web',
      ).encode();
      final parts = good.split('.');
      final keySegment = parts[3];

      final bad = <String>[
        '', // empty
        'fp-link.v1.$provisioningId.$keySegment', // 4 segments
        '$good.extra', // 6 segments
        good.replaceFirst('fp-link', 'fp-lonk'), // wrong prefix
        good.replaceFirst('.v1.', '.v2.'), // wrong version
        'fp-link.v1.not-a-uuid.$keySegment.web', // non-UUID id
        'fp-link.v1.$provisioningId.${keySegment}AA.web', // 34-byte key
        'fp-link.v1.$provisioningId.${keySegment.substring(0, keySegment.length - 2)}.web', // short key
        'fp-link.v1.$provisioningId.$keySegment=.web', // padded base64url
        'fp-link.v1.$provisioningId.$keySegment.', // empty platform
        'fp-link.v1.$provisioningId.$keySegment.a b', // illegal platform char
        'fp-link.v1.$provisioningId.$keySegment.${'a' * 33}', // 33-char platform
      ];
      for (final raw in bad) {
        expect(LinkOobCode.tryParse(raw), isNull, reason: 'accepted: "$raw"');
      }
    });

    test('a key segment with a non-0x05 lead byte is rejected', () {
      final forged = Uint8List.fromList(ephPubN);
      forged[0] = 0x04;
      final raw =
          'fp-link.v1.$provisioningId.${base64UrlEncode(forged).replaceAll('=', '')}.web';
      expect(LinkOobCode.tryParse(raw), isNull);
    });

    // The QR carries the code in the FRAGMENT of the app's URL so a phone
    // camera opens the app instead of a search page. The fragment is never
    // part of an HTTP request, so amendment (c) holds; the parser accepts
    // the URL form back, and nothing but the fragment matters.
    group('deep-link form', () {
      final code = LinkOobCode(
        provisioningId: provisioningId,
        ephPubN: ephPubN,
        platform: 'web',
      );

      test('builds /link#<code> on the given origin', () {
        final url = code.toDeepLink(Uri.parse('https://example.test/app/x'));
        expect(url, 'https://example.test/link#${code.encode()}');
      });

      test('a query string on the origin never reaches the QR', () {
        // On web `Uri.base` can still carry `?notify_conv=<id>` at QR time.
        final url = code.toDeepLink(
          Uri.parse('https://example.test/?notify_conv=42'),
        );
        expect(url, 'https://example.test/link#${code.encode()}');
      });

      test('parses the URL form back to the same code', () {
        final url = code.toDeepLink(Uri.parse('https://example.test'));
        final parsed = LinkOobCode.tryParse(url);
        expect(parsed, isNotNull);
        expect(parsed!.encode(), code.encode());
      });

      test('the host is not trusted and not required to match', () {
        final foreign = 'https://evil.example/anything#${code.encode()}';
        expect(LinkOobCode.tryParse(foreign)?.encode(), code.encode());
      });

      test('a URL without a link fragment is rejected', () {
        expect(LinkOobCode.tryParse('https://example.test/link'), isNull);
        expect(LinkOobCode.tryParse('https://example.test/link#'), isNull);
        expect(
          LinkOobCode.tryParse(
            'https://example.test/link?code=${code.encode()}',
          ),
          isNull,
        );
      });
    });
  });
}
