import 'dart:convert';
import 'dart:typed_data';

import 'package:webcrypto/webcrypto.dart';

/// The binary envelope for a decrypted voice-note file sealed under a content
/// key before it enters the native audio cache.
///
/// ```text
/// FPAE | version (1) | kid length (1) | kid UTF-8 | IV (12) | AES-256-GCM ciphertext + tag
/// ```
///
/// The key id is deliberately cleartext. A rotation pass must find files
/// sealed under a retiring key without first decrypting every audio file; the
/// same trade-off is made by the sealed-record envelope in
/// [PlaintextRecordCodec]. It reveals which local content key protects a file,
/// but not its audio bytes.
///
/// Destroying a content key makes files sealed from their first write
/// unreadable. It cannot erase plaintext from legacy cache files, filesystem
/// journals, or flash wear-levelled blocks that held an earlier copy. This
/// codec provides cryptographic unreadability for its sealed bytes, not a
/// guarantee that storage media contains no historical residue.
class SealedAudioCodec {
  SealedAudioCodec._();

  static const int _version = 1;
  static const int _magicLength = 4;
  static const int _kidLengthOffset = _magicLength + 1;
  static const int _kidOffset = _kidLengthOffset + 1;
  static const int _ivLength = 12;
  static final Uint8List _magic = Uint8List.fromList(ascii.encode('FPAE'));

  /// Encrypts [plaintext] with [keyBytes] using a fresh AES-GCM IV.
  ///
  /// A content key is AES-256, so accepting any other length would produce a
  /// file this format does not promise to support.
  static Future<Uint8List> seal({
    required String kid,
    required Uint8List keyBytes,
    required Uint8List plaintext,
  }) async {
    if (keyBytes.length != 32) {
      throw ArgumentError.value(keyBytes.length, 'keyBytes', 'must be 32 bytes');
    }

    final kidBytes = Uint8List.fromList(utf8.encode(kid));
    if (kidBytes.length > 0xff) {
      throw ArgumentError.value(kid, 'kid', 'UTF-8 form must fit in 255 bytes');
    }

    final iv = Uint8List(_ivLength);
    fillRandomBytes(iv);

    final key = await AesGcmSecretKey.importRawKey(keyBytes);
    final ciphertext = await key.encryptBytes(plaintext, iv);
    final ciphertextBytes = Uint8List.fromList(ciphertext);
    final headerLength = _kidOffset + kidBytes.length + _ivLength;
    final sealed = Uint8List(headerLength + ciphertextBytes.length);

    sealed.setRange(0, _magicLength, _magic);
    sealed[_magicLength] = _version;
    sealed[_kidLengthOffset] = kidBytes.length;
    sealed.setRange(_kidOffset, _kidOffset + kidBytes.length, kidBytes);
    sealed.setRange(_kidOffset + kidBytes.length, headerLength, iv);
    sealed.setRange(headerLength, sealed.length, ciphertextBytes);
    return sealed;
  }

  /// Reads the cleartext key id without attempting decryption.
  ///
  /// Null means [bytes] is not a complete header this build understands; a
  /// caller must not mistake it for a legacy audio payload after this returns
  /// null unless its enclosing storage format says that is safe.
  static String? kidOf(Uint8List bytes) => _readHeader(bytes)?.kid;

  /// Whether [bytes] carries a complete, supported sealed-file header.
  static bool isSealed(Uint8List bytes) => _readHeader(bytes) != null;

  /// Decrypts a sealed audio file, returning null rather than throwing for
  /// malformed bytes, an incorrect key, or a failed GCM authentication tag.
  ///
  /// Null never represents an empty audio file: a successful empty plaintext
  /// is returned as an empty [Uint8List].
  static Future<Uint8List?> unseal({
    required Uint8List bytes,
    required Uint8List keyBytes,
  }) async {
    final header = _readHeader(bytes);
    if (header == null || bytes.length == header.ciphertextOffset) return null;

    try {
      final key = await AesGcmSecretKey.importRawKey(keyBytes);
      final plaintext = await key.decryptBytes(
        Uint8List.sublistView(bytes, header.ciphertextOffset),
        Uint8List.sublistView(bytes, header.ivOffset, header.ciphertextOffset),
      );
      return Uint8List.fromList(plaintext);
    } catch (_) {
      return null;
    }
  }

  static _SealedAudioHeader? _readHeader(Uint8List bytes) {
    if (bytes.length < _kidOffset) return null;
    for (var i = 0; i < _magicLength; i++) {
      if (bytes[i] != _magic[i]) return null;
    }
    if (bytes[_magicLength] != _version) return null;

    final kidLength = bytes[_kidLengthOffset];
    final ivOffset = _kidOffset + kidLength;
    final ciphertextOffset = ivOffset + _ivLength;
    if (bytes.length < ciphertextOffset) return null;

    try {
      return _SealedAudioHeader(
        kid: utf8.decode(Uint8List.sublistView(bytes, _kidOffset, ivOffset)),
        ivOffset: ivOffset,
        ciphertextOffset: ciphertextOffset,
      );
    } catch (_) {
      return null;
    }
  }
}

class _SealedAudioHeader {
  const _SealedAudioHeader({
    required this.kid,
    required this.ivOffset,
    required this.ciphertextOffset,
  });

  final String kid;
  final int ivOffset;
  final int ciphertextOffset;
}
