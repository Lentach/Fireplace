import 'dart:convert';
import 'dart:typed_data';

/// Cleartext framing of a sealed web content value:
/// `fps1:<kid>:<cid|->:<base64(12-byte IV || AES-256-GCM ct+tag)>`.
///
/// Everything OUTSIDE the base64 payload is deliberately readable without the
/// content key (see `docs/design/web-content-sealing.md` §3.1):
///
///  * `kid` names the sealing key so key-loss detection and future rotation
///    can find rows without unsealing them (same role as the Android store's
///    cleartext `kid` column);
///  * `cid` is the record's conversation id — the erasure-completeness rule:
///    a user-requested "delete this conversation" must be able to select a
///    sealed row even in a session that cannot unseal it (fallback, rollback,
///    proven key loss). `-` for values that carry no conversation (the
///    raw-replay and pendsend families, and pre-`_cid` legacy records).
///
/// The `fps1:` prefix is the read-both discriminator against legacy plaintext
/// values, which are JSON (`{`-prefixed) or raw base64 and can never collide.
class SealedWebEnvelope {
  const SealedWebEnvelope({
    required this.kid,
    required this.cid,
    required this.bytes,
  });

  static const String prefix = 'fps1:';

  final String kid;
  final int? cid;

  /// `12-byte IV || ciphertext+tag`, the [ContentSealer] wire shape.
  final Uint8List bytes;

  static bool isEnvelope(String value) => value.startsWith(prefix);

  String encode() => '$prefix$kid:${cid ?? '-'}:${base64Encode(bytes)}';

  /// Strict parse: null for anything that is not a well-formed envelope —
  /// callers treat such a value as legacy plaintext (read-both) or as an
  /// unclassifiable record, never as empty content.
  static SealedWebEnvelope? tryParse(String value) {
    if (!value.startsWith(prefix)) return null;
    final body = value.substring(prefix.length);
    final kidEnd = body.indexOf(':');
    if (kidEnd <= 0) return null;
    final cidEnd = body.indexOf(':', kidEnd + 1);
    if (cidEnd < 0) return null;
    final kid = body.substring(0, kidEnd);
    final cidRaw = body.substring(kidEnd + 1, cidEnd);
    int? cid;
    if (cidRaw != '-') {
      cid = int.tryParse(cidRaw);
      if (cid == null) return null;
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(body.substring(cidEnd + 1));
    } catch (_) {
      return null;
    }
    // 12-byte IV + at least the 16-byte GCM tag; anything shorter cannot be a
    // real seal and must not be classified as one.
    if (bytes.length < 13) return null;
    return SealedWebEnvelope(kid: kid, cid: cid, bytes: bytes);
  }
}
