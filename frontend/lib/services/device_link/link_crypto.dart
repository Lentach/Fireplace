// §5.1 provisioning-ceremony crypto (Phase 2 T3, spec §12 2026-08-20 item
// (ii) — byte-exact, NORMATIVE).
//
// Everything here is the EXPLICIT construction the spec requires: the stock
// `ProvisioningCipher` is FORBIDDEN (it mints its own internal ephemeral,
// which would bypass the SAS-verified secret). Building blocks:
//
//   S_dh       = Curve.calculateAgreement(theirEphPub, ownEphPriv)   (32 B)
//   transcript = utf8(provisioningId) ‖ ephPubN(33) ‖ ephPubP(33)
//   SAS bytes  = HKDF(ikm=S_dh, info=utf8("fp-link-sas")  ‖ transcript, 32)
//   blob keys  = HKDF(ikm=S_dh, info=utf8("fp-link-blob") ‖ transcript, 64)
//   blob       = 0x01 ‖ IV(16) ‖ AES-256-CBC ct ‖ HMAC(0x01‖IV‖ct)(32)
//
// The KDF is a LOCAL RFC-5869 HKDF-SHA256 with salt = 32 zero bytes —
// byte-identical to libsignal's HKDFv3 under a null salt, which is not
// exported from the 0.8.2 barrel (and src/ implementation imports are
// forbidden). AES-CBC/PKCS7 rides pointycastle, the same engine libsignal's
// internal cbc.dart uses.
//
// Library caveat honored throughout (same discipline as
// device_authority_engine.dart): libsignal's curve calls MUTATE buffers they
// are handed — every retained key/message buffer crosses that boundary as a
// fresh copy.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:pointycastle/export.dart'
    show
        AESEngine,
        CBCBlockCipher,
        KeyParameter,
        ParametersWithIV,
        PKCS7Padding;

/// Serialized Curve25519 public keys: 33 bytes with a leading 0x05.
const int kLinkEphemeralPublicKeyLength = 33;

const int _kBlobVersionByte = 0x01;
const int _kIvLength = 16;
const int _kMacLength = 32;
const String _kSasInfoLabel = 'fp-link-sas';
const String _kBlobInfoLabel = 'fp-link-blob';

/// A rejected blob. [reason] is `bad_mac` (tamper — detected BEFORE any
/// decrypt) or `malformed` (structure/JSON violations).
class LinkBlobException implements Exception {
  const LinkBlobException(this.reason);

  final String reason;

  @override
  String toString() => 'LinkBlobException($reason)';
}

/// Fresh Curve25519 ephemeral for one ceremony side.
ECKeyPair generateLinkEphemeral() => Curve.generateKeyPair();

/// The 33-byte serialized public half, as a caller-owned copy.
Uint8List linkEphemeralPublicBytes(ECKeyPair pair) =>
    Uint8List.fromList(pair.publicKey.serialize());

/// RFC-5869 HKDF-SHA256 with salt fixed to 32 zero bytes (spec item (ii);
/// byte-identical to libsignal HKDFv3 with a null salt). Expand counter
/// starts at 0x01 per the RFC.
Uint8List hkdfSha256({
  required Uint8List ikm,
  required Uint8List info,
  required int length,
}) {
  if (length <= 0 || length > 255 * 32) {
    throw ArgumentError('length out of RFC-5869 range');
  }
  final prk = Hmac(sha256, Uint8List(32)).convert(ikm).bytes;
  final okm = <int>[];
  var block = <int>[];
  var counter = 1;
  while (okm.length < length) {
    block = Hmac(sha256, prk).convert(<int>[...block, ...info, counter]).bytes;
    okm.addAll(block);
    counter++;
  }
  return Uint8List.fromList(okm.sublist(0, length));
}

/// `S_dh` — the raw 32-byte ECDH secret. [theirEphPub] is the peer's 33-byte
/// serialized public key; it is decoded from a copy so the caller's buffer
/// survives the library's in-place normalization.
Uint8List linkSharedSecret({
  required Uint8List theirEphPub,
  required ECPrivateKey ownEphPriv,
}) {
  if (theirEphPub.length != kLinkEphemeralPublicKeyLength) {
    throw ArgumentError(
      'ephemeral public key must be $kLinkEphemeralPublicKeyLength bytes',
    );
  }
  final theirKey = Curve.decodePoint(Uint8List.fromList(theirEphPub), 0);
  return Curve.calculateAgreement(theirKey, ownEphPriv);
}

/// `transcript = utf8(provisioningId) ‖ ephPubN(33) ‖ ephPubP(33)` —
/// fixed N-then-P order on BOTH sides (spec item (ii)).
Uint8List linkTranscript({
  required String provisioningId,
  required Uint8List ephPubN,
  required Uint8List ephPubP,
}) {
  if (ephPubN.length != kLinkEphemeralPublicKeyLength ||
      ephPubP.length != kLinkEphemeralPublicKeyLength) {
    throw ArgumentError(
      'ephemeral public keys must be $kLinkEphemeralPublicKeyLength bytes',
    );
  }
  return Uint8List.fromList([
    ...utf8.encode(provisioningId),
    ...ephPubN,
    ...ephPubP,
  ]);
}

/// The human SAS code: first 4 bytes of the 32-byte `fp-link-sas` derivation
/// read as a big-endian uint32, mod 10^6, zero-padded to 6 digits, rendered
/// as two groups of three (`XXX XXX` — the ~20-bit comparison of §5.1).
String deriveLinkSas({
  required Uint8List sharedSecret,
  required Uint8List transcript,
}) {
  final bytes = hkdfSha256(
    ikm: sharedSecret,
    info: Uint8List.fromList([...utf8.encode(_kSasInfoLabel), ...transcript]),
    length: 32,
  );
  final value = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);
  final digits = (value % 1000000).toString().padLeft(6, '0');
  return '${digits.substring(0, 3)} ${digits.substring(3)}';
}

/// The blob's AES-256-CBC key (bytes 0–31) and HMAC-SHA-256 key (32–63).
class LinkBlobKeys {
  const LinkBlobKeys({required this.aesKey, required this.macKey});

  final Uint8List aesKey;
  final Uint8List macKey;
}

LinkBlobKeys deriveLinkBlobKeys({
  required Uint8List sharedSecret,
  required Uint8List transcript,
}) {
  final okm = hkdfSha256(
    ikm: sharedSecret,
    info: Uint8List.fromList([...utf8.encode(_kBlobInfoLabel), ...transcript]),
    length: 64,
  );
  return LinkBlobKeys(
    aesKey: Uint8List.sublistView(okm, 0, 32),
    macKey: Uint8List.sublistView(okm, 32, 64),
  );
}

/// Blob plaintext (spec item (ii)): the identity the primary hands to N,
/// plus the enrollment record fields N needs to re-verify its own chain.
class LinkBlobPayload {
  const LinkBlobPayload({
    required this.userId,
    required this.deviceId,
    required this.ikPub,
    required this.ikPriv,
    required this.dakPub,
    required this.enrollmentCreatedAt,
    required this.enrollmentSig,
  });

  /// Strict parse: every field present with its exact type, no extras.
  /// Anything else is [LinkBlobException] `malformed`.
  factory LinkBlobPayload.fromJson(Map<String, dynamic> json) {
    const expectedKeys = {
      'userId',
      'deviceId',
      'ikPub',
      'ikPriv',
      'dakPub',
      'enrollmentCreatedAt',
      'enrollmentSig',
    };
    if (json.length != expectedKeys.length ||
        !json.keys.every(expectedKeys.contains)) {
      throw const LinkBlobException('malformed');
    }
    final userId = json['userId'];
    final deviceId = json['deviceId'];
    final ikPub = json['ikPub'];
    final ikPriv = json['ikPriv'];
    final dakPub = json['dakPub'];
    final enrollmentCreatedAt = json['enrollmentCreatedAt'];
    final enrollmentSig = json['enrollmentSig'];
    if (userId is! int ||
        deviceId is! int ||
        ikPub is! String ||
        ikPriv is! String ||
        dakPub is! String ||
        enrollmentCreatedAt is! int ||
        enrollmentSig is! String) {
      throw const LinkBlobException('malformed');
    }
    return LinkBlobPayload(
      userId: userId,
      deviceId: deviceId,
      ikPub: ikPub,
      ikPriv: ikPriv,
      dakPub: dakPub,
      enrollmentCreatedAt: enrollmentCreatedAt,
      enrollmentSig: enrollmentSig,
    );
  }

  final int userId;
  final int deviceId;

  /// base64 — serialized identity public key.
  final String ikPub;

  /// base64 — serialized identity PRIVATE key. Exists only inside the sealed
  /// blob; never logged, never sent outside it (I1).
  final String ikPriv;

  /// base64 — serialized DAK public key.
  final String dakPub;

  /// Milliseconds since epoch, exactly as signed in the enrollment record E.
  final int enrollmentCreatedAt;

  /// base64 — sig_IK("fp-enroll-v1\0" ‖ …).
  final String enrollmentSig;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'userId': userId,
    'deviceId': deviceId,
    'ikPub': ikPub,
    'ikPriv': ikPriv,
    'dakPub': dakPub,
    'enrollmentCreatedAt': enrollmentCreatedAt,
    'enrollmentSig': enrollmentSig,
  };
}

Uint8List _aesCbc({
  required bool encrypt,
  required Uint8List key,
  required Uint8List iv,
  required Uint8List input,
}) {
  final cbc = CBCBlockCipher(AESEngine())
    ..init(
      encrypt,
      ParametersWithIV(
        KeyParameter(Uint8List.fromList(key)),
        Uint8List.fromList(iv),
      ),
    );
  final out = Uint8List(input.length);
  var offset = 0;
  while (offset < input.length) {
    offset += cbc.processBlock(input, offset, out, offset);
  }
  return out;
}

/// Encrypt-then-MAC seal: `0x01 ‖ IV(16) ‖ ct ‖ HMAC(0x01‖IV‖ct)(32)`.
Uint8List sealLinkBlob({
  required LinkBlobKeys keys,
  required LinkBlobPayload payload,
}) {
  final random = Random.secure();
  final iv = Uint8List.fromList(
    List<int>.generate(_kIvLength, (_) => random.nextInt(256)),
  );
  final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  final padLength = 16 - (plaintext.length % 16);
  final padded = Uint8List(plaintext.length + padLength)..setAll(0, plaintext);
  PKCS7Padding().addPadding(padded, plaintext.length);
  final ciphertext = _aesCbc(
    encrypt: true,
    key: keys.aesKey,
    iv: iv,
    input: padded,
  );
  final macInput = Uint8List.fromList([
    _kBlobVersionByte,
    ...iv,
    ...ciphertext,
  ]);
  final mac = Hmac(sha256, keys.macKey).convert(macInput).bytes;
  return Uint8List.fromList([...macInput, ...mac]);
}

/// Constant-time equality: full-length bitwise-OR accumulate, no early exit.
bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Opens a sealed blob: structure check, CONSTANT-TIME MAC verification
/// strictly BEFORE any decrypt (falsification 8's client half — a blob keyed
/// to a different ephemeral dies here as `bad_mac`), then AES-CBC decrypt,
/// PKCS7 unpad, and strict JSON parse.
LinkBlobPayload openLinkBlob({
  required LinkBlobKeys keys,
  required Uint8List blob,
}) {
  // Minimum: version ‖ IV ‖ one cipher block ‖ MAC.
  if (blob.length < 1 + _kIvLength + 16 + _kMacLength) {
    throw const LinkBlobException('malformed');
  }
  if (blob[0] != _kBlobVersionByte) {
    throw const LinkBlobException('malformed');
  }
  final ciphertextLength = blob.length - 1 - _kIvLength - _kMacLength;
  if (ciphertextLength % 16 != 0) {
    throw const LinkBlobException('malformed');
  }
  final macInput = Uint8List.sublistView(blob, 0, blob.length - _kMacLength);
  final mac = Uint8List.sublistView(blob, blob.length - _kMacLength);
  final expected = Hmac(sha256, keys.macKey).convert(macInput).bytes;
  if (!_constantTimeEquals(expected, mac)) {
    throw const LinkBlobException('bad_mac');
  }

  final iv = Uint8List.sublistView(blob, 1, 1 + _kIvLength);
  final ciphertext = Uint8List.sublistView(
    blob,
    1 + _kIvLength,
    blob.length - _kMacLength,
  );
  final Uint8List plaintext;
  try {
    final padded = _aesCbc(
      encrypt: false,
      key: keys.aesKey,
      iv: iv,
      input: Uint8List.fromList(ciphertext),
    );
    final padCount = PKCS7Padding().padCount(padded);
    plaintext = Uint8List.sublistView(padded, 0, padded.length - padCount);
  } catch (_) {
    throw const LinkBlobException('malformed');
  }
  final dynamic decoded;
  try {
    decoded = jsonDecode(utf8.decode(plaintext));
  } catch (_) {
    throw const LinkBlobException('malformed');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const LinkBlobException('malformed');
  }
  return LinkBlobPayload.fromJson(decoded);
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final RegExp _platformPattern = RegExp(r'^[A-Za-z0-9_-]{1,32}$');

/// Path of the QR deep link. Served by the SPA fallback (nginx `try_files …
/// /index.html`); it collides with no proxied API prefix and needs no server
/// route. The payload rides the fragment, never the path or query.
const String kLinkDeepLinkPath = '/link';

/// The out-of-band code (spec item (i)): the exact ASCII string
/// `fp-link.v1.<provisioningId>.<base64url(ephPubN), no padding>.<platform>`.
/// This is the ONLY channel `ephPubN` ever travels (amendment (c)) — QR and
/// manual paste are the same channel: N's screen → human → primary.
class LinkOobCode {
  const LinkOobCode({
    required this.provisioningId,
    required this.ephPubN,
    required this.platform,
  });

  final String provisioningId;

  /// 33-byte serialized ephemeral public key of the NEW device.
  final Uint8List ephPubN;

  /// N's self-reported platform label — informational metadata for the
  /// signed list entry, ≤32 chars.
  final String platform;

  String encode() {
    final b64url = base64UrlEncode(ephPubN).replaceAll('=', '');
    return 'fp-link.v1.$provisioningId.$b64url.$platform';
  }

  /// The QR form: the code carried in the FRAGMENT of the app's own URL, so
  /// a phone camera opens the installed app instead of a search page, and
  /// the browser never sends it anywhere — fragments are not part of an HTTP
  /// request, so amendment (c) ("ephPubN never transits the server") holds
  /// byte for byte. [tryParse] accepts this form back, and the plain code.
  String toDeepLink(Uri origin) =>
      origin.replace(path: kLinkDeepLinkPath, fragment: encode()).toString();

  /// Strict parse; ANY violation returns null, never a partial result.
  /// Accepts the bare code or a [toDeepLink] URL (any origin: the fragment
  /// is the payload, the host is only what the camera needed to open us).
  static LinkOobCode? tryParse(String raw) {
    var text = raw.trim();
    if (!text.startsWith('fp-link.')) {
      final uri = Uri.tryParse(text);
      if (uri == null || uri.fragment.isEmpty) return null;
      text = uri.fragment;
    }
    final parts = text.split('.');
    if (parts.length != 5) return null;
    if (parts[0] != 'fp-link' || parts[1] != 'v1') return null;
    final provisioningId = parts[2];
    if (!_uuidPattern.hasMatch(provisioningId)) return null;
    final keySegment = parts[3];
    // No padding by construction; '=' anywhere means a non-canonical form.
    if (keySegment.isEmpty || keySegment.contains('=')) return null;
    final Uint8List ephPubN;
    try {
      final padded = keySegment + '=' * ((4 - keySegment.length % 4) % 4);
      ephPubN = base64Url.decode(padded);
    } catch (_) {
      return null;
    }
    if (ephPubN.length != kLinkEphemeralPublicKeyLength) return null;
    // Canonical form: re-encoding must reproduce the segment exactly.
    if (base64UrlEncode(ephPubN).replaceAll('=', '') != keySegment) {
      return null;
    }
    // Leading type byte of a serialized Curve25519 public key.
    if (ephPubN[0] != 0x05) return null;
    final platform = parts[4];
    if (!_platformPattern.hasMatch(platform)) return null;
    return LinkOobCode(
      provisioningId: provisioningId,
      ephPubN: ephPubN,
      platform: platform,
    );
  }
}
