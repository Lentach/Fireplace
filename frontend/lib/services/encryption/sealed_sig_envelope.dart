import 'dart:convert';
import 'dart:typed_data';

/// A read/write against sealed Signal material failed in a way that MUST NOT
/// be interpreted as absence (docs/design/web-sig-sealing.md §2 rule 1).
///
/// Absence answers drive catastrophic transitions — identity regeneration,
/// fresh `SessionRecord()` over a live ratchet, prekey id reuse — so an
/// unsealable value PROPAGATES as this throw: the operation fails transiently
/// (retryable next call / next boot) and nothing regenerates, resets, or
/// reuses. Callers may catch it only to surface "E2E unavailable", never to
/// substitute a default.
class SigStoreUnreadable implements Exception {
  const SigStoreUnreadable(this.stage);

  /// Which gate refused: `seal`, `parse`, `kid`, `unseal`,
  /// `fallback-superseded`.
  final String stage;

  @override
  String toString() =>
      'SigStoreUnreadable($stage): sealed Signal material could not be '
      'processed; treating this as absence would destroy the identity';
}

/// The sealed sig store could not open (docs/design/web-sig-sealing.md §3.2).
///
/// [fallbackLegal] carries the rule-4 decision: true ONLY when a SUCCESSFUL
/// backing-store probe found zero `fpsig1:` rows (pre-first-seal world —
/// plaintext fallback is the status quo, loudly diagnosed). False means
/// sealed rows exist or their existence is UNKNOWN (probe failed): the
/// session must run with E2E unavailable rather than beside sealed rows.
class SigSealOpenUnavailable implements Exception {
  const SigSealOpenUnavailable(this.stage, {required this.fallbackLegal});

  final String stage;
  final bool fallbackLegal;

  @override
  String toString() =>
      'SigSealOpenUnavailable($stage, fallbackLegal: $fallbackLegal)';
}

/// Parsed `fpsig1:<kid>:<base64(12B IV || AES-256-GCM ct+tag)>` value.
///
/// Distinct magic from the content store's `fps1:` so the two families can
/// never cross-decode; no `cid` slot (sig rows are not conversation-erasure
/// targets, and the peer id already lives in the cleartext key name).
class SealedSigEnvelope {
  const SealedSigEnvelope({required this.kid, required this.bytes});

  static const String prefix = 'fpsig1:';

  final String kid;

  /// `12-byte IV || ciphertext+tag`, always ≥ 13 bytes.
  final Uint8List bytes;

  /// Cheap discriminator for read-both and the open-time probe.
  static bool isEnvelope(String value) => value.startsWith(prefix);

  static String encode(String kid, Uint8List sealed) =>
      '$prefix$kid:${base64Encode(sealed)}';

  /// Strict parse; null for anything malformed. Callers MUST NOT treat a
  /// null here as plaintext when [isEnvelope] already matched — that is the
  /// `parse` failure stage of [SigStoreUnreadable].
  static SealedSigEnvelope? tryParse(String value) {
    if (!value.startsWith(prefix)) return null;
    final rest = value.substring(prefix.length);
    final sep = rest.indexOf(':');
    if (sep <= 0) return null;
    final kid = rest.substring(0, sep);
    final b64 = rest.substring(sep + 1);
    if (b64.isEmpty) return null;
    Uint8List bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      return null;
    }
    if (bytes.length < 13) return null;
    return SealedSigEnvelope(kid: kid, bytes: bytes);
  }
}
