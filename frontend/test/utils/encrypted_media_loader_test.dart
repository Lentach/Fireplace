import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/api_service.dart';
import 'package:fireplace/services/media_crypto_service.dart';
import 'package:fireplace/utils/encrypted_media_loader.dart';

class _FakeApi extends ApiService {
  _FakeApi(this._bytes) : super(baseUrl: 'http://test');
  final Uint8List _bytes;
  String? lastUrl;
  String? lastToken;

  @override
  Future<Uint8List> fetchMediaBytes(String url, String token) async {
    lastUrl = url;
    lastToken = token;
    return _bytes;
  }
}

class _FakeCrypto extends MediaCryptoService {
  bool called = false;
  String? key;
  String? iv;

  @override
  Future<Uint8List> decrypt(Uint8List ciphertext, String keyB64, String ivB64) async {
    called = true;
    key = keyB64;
    iv = ivB64;
    return Uint8List.fromList(const [9, 9, 9]);
  }
}

void main() {
  group('loadDecryptedMediaBytes', () {
    test('no key/iv returns raw fetched bytes without decrypting', () async {
      final api = _FakeApi(Uint8List.fromList(const [1, 2, 3]));
      final crypto = _FakeCrypto();

      final out = await loadDecryptedMediaBytes(
        url: 'u',
        token: 't',
        api: api,
        crypto: crypto,
      );

      expect(out, [1, 2, 3]);
      expect(crypto.called, isFalse);
      expect(api.lastUrl, 'u');
      expect(api.lastToken, 't');
    });

    test('decrypts when both key and iv are present', () async {
      final api = _FakeApi(Uint8List.fromList(const [4, 5]));
      final crypto = _FakeCrypto();

      final out = await loadDecryptedMediaBytes(
        url: 'u',
        token: 't',
        key: 'K',
        iv: 'IV',
        api: api,
        crypto: crypto,
      );

      expect(out, [9, 9, 9]);
      expect(crypto.called, isTrue);
      expect(crypto.key, 'K');
      expect(crypto.iv, 'IV');
    });

    test('throws when fetched media exceeds the size cap', () async {
      final api = _FakeApi(Uint8List(MediaCryptoService.maxBytes + 1));

      expect(
        () => loadDecryptedMediaBytes(url: 'u', token: 't', api: api),
        throwsA(isA<Exception>()),
      );
    });
  });
}
