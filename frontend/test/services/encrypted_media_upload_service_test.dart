import 'dart:typed_data';

import 'package:fireplace/services/api_service.dart';
import 'package:fireplace/services/encrypted_media_upload_service.dart';
import 'package:fireplace/services/media_crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCrypto extends MediaCryptoService {
  @override
  Future<EncryptedMedia> encrypt(Uint8List bytes) async => EncryptedMedia(
        ciphertext: Uint8List.fromList([9, 9, 9]),
        keyBase64: 'KEY',
        ivBase64: 'IV',
      );
}

class _FakeApi extends ApiService {
  _FakeApi() : super(baseUrl: 'http://test');
  Map<String, Object?>? lastArgs;
  final List<String> events = [];

  @override
  Future<Map<String, dynamic>> uploadEncryptedMedia({
    required String token,
    required Uint8List encryptedBytes,
    required String mediaType,
    int? duration,
    int? expiresIn,
    String? fileName,
  }) async {
    events.add('upload');
    lastArgs = {
      'token': token,
      'mediaType': mediaType,
      'duration': duration,
      'expiresIn': expiresIn,
      'fileName': fileName,
      'bytesLen': encryptedBytes.length,
    };
    return {'mediaUrl': 'http://test/media/msgs/abc.bin', 'mediaDuration': 7};
  }
}

void main() {
  group('EncryptedMediaUploadService', () {
    test('returns mediaUrl + key/iv and parses mediaDuration', () async {
      final api = _FakeApi();
      final svc = EncryptedMediaUploadService(api: api, crypto: _FakeCrypto());

      final result = await svc.encryptAndUpload(
        bytes: Uint8List.fromList([1, 2, 3]),
        token: 'tok',
        mediaType: 'voice',
        duration: 5,
        expiresIn: 60,
      );

      expect(result.mediaUrl, 'http://test/media/msgs/abc.bin');
      expect(result.keyBase64, 'KEY');
      expect(result.ivBase64, 'IV');
      expect(result.mediaDuration, 7);
    });

    test('passes mediaType/duration/expiresIn/fileName through to the api', () async {
      final api = _FakeApi();
      final svc = EncryptedMediaUploadService(api: api, crypto: _FakeCrypto());

      await svc.encryptAndUpload(
        bytes: Uint8List.fromList([1]),
        token: 'tok',
        mediaType: 'file',
        fileName: 'doc.pdf',
      );

      expect(api.lastArgs!['mediaType'], 'file');
      expect(api.lastArgs!['fileName'], 'doc.pdf');
      expect(api.lastArgs!['expiresIn'], isNull);
      expect(api.lastArgs!['duration'], isNull);
    });

    test('fires onEncrypted BEFORE the upload await (invariant)', () async {
      final api = _FakeApi();
      final svc = EncryptedMediaUploadService(api: api, crypto: _FakeCrypto());

      await svc.encryptAndUpload(
        bytes: Uint8List.fromList([1]),
        token: 'tok',
        mediaType: 'image',
        onEncrypted: (key, iv) {
          api.events.add('encrypted:$key:$iv');
        },
      );

      expect(api.events, ['encrypted:KEY:IV', 'upload']);
    });
  });
}
