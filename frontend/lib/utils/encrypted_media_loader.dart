import 'dart:typed_data';

import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/media_crypto_service.dart';

/// Fetch [url] with [token], enforce the media size cap, and AES-GCM decrypt
/// when both [key] and [iv] are present.
///
/// Extracted from the image / GIF / file message widgets, which each ran an
/// identical fetch + size-guard + optional-decrypt pipeline. This THROWS on any
/// failure (fetch error, oversize, decrypt failure); callers catch and render
/// their own existing failure UI (image -> error text, GIF -> broken-image
/// icon, file -> snackbar). [api]/[crypto] are injectable for testing.
Future<Uint8List> loadDecryptedMediaBytes({
  required String url,
  required String token,
  String? key,
  String? iv,
  String? baseUrl,
  ApiService? api,
  MediaCryptoService? crypto,
}) async {
  final service = api ?? ApiService(baseUrl: baseUrl ?? AppConfig.baseUrl);
  final raw = await service.fetchMediaBytes(url, token);
  final encrypted = key != null && iv != null;
  final cap = encrypted
      ? MediaCryptoService.maxCiphertextBytes
      : MediaCryptoService.maxBytes;
  if (raw.length > cap) {
    throw Exception('Media too large (${raw.length} > $cap)');
  }
  if (key != null && iv != null) {
    return (crypto ?? MediaCryptoService())
        .decrypt(Uint8List.fromList(raw), key, iv);
  }
  return Uint8List.fromList(raw);
}
