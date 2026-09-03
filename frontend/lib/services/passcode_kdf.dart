import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:webcrypto/webcrypto.dart';

/// Password-stretching seam for the app-level Passcode Lock.
///
/// Abstract for the same reason [ContentSealer] is
/// (`services/encryption/content_sealer.dart`): the passcode state machine —
/// enable, unlock, attempt backoff, auto-lock — must be testable on hosts
/// where the webcrypto native library is not set up, and those tests are
/// about state, not ciphers. Production always uses [Pbkdf2PasscodeKdf]; the
/// real primitive is covered by its own skip-gracefully tests plus the
/// on-device acceptance run.
abstract class PasscodeKdf {
  /// Derives [lengthBytes] of key material from [passcode] and [salt].
  Future<Uint8List> derive({
    required String passcode,
    required Uint8List salt,
    required int iterations,
    int lengthBytes = 32,
  });
}

/// Work factor for the stored verifier. OWASP's 2023 floor for
/// PBKDF2-HMAC-SHA256 is 600k iterations; WebCrypto and BoringSSL both do
/// that in a few hundred milliseconds, which is invisible on a lock screen.
///
/// Honest limit: a 4-digit code is only ~10k candidates, so iteration count
/// buys a factor, not safety, against an attacker who can READ the stored
/// verifier. On Android the verifier sits in the Keystore-backed secure
/// storage behind `FLAG_SECURE`; on web it is localStorage and readable by
/// anything with devtools — which is why v1 is a UI gate and the at-rest
/// key-wrapping tier is a separate, opt-in phase.
const int kPasscodeKdfIterations = 600000;

/// PBKDF2-HMAC-SHA256 via `package:webcrypto` (WebCrypto in the browser,
/// BoringSSL on Android — the same package the media and content paths use).
class Pbkdf2PasscodeKdf implements PasscodeKdf {
  const Pbkdf2PasscodeKdf();

  @override
  Future<Uint8List> derive({
    required String passcode,
    required Uint8List salt,
    required int iterations,
    int lengthBytes = 32,
  }) async {
    final key = await Pbkdf2SecretKey.importRawKey(
      Uint8List.fromList(utf8.encode(passcode)),
    );
    final bits = await key.deriveBits(
      lengthBytes * 8,
      Hash.sha256,
      salt,
      iterations,
    );
    return Uint8List.fromList(bits);
  }
}

/// 16 random bytes from the platform CSPRNG.
///
/// `dart:math`'s [Random.secure] rather than webcrypto's `fillRandomBytes` on
/// purpose: salt generation must work on a host without the native library,
/// so enabling a passcode never depends on the same setup the cipher does.
Uint8List generatePasscodeSalt() {
  final rng = Random.secure();
  final salt = Uint8List(16);
  for (var i = 0; i < salt.length; i++) {
    salt[i] = rng.nextInt(256);
  }
  return salt;
}

/// Length-checked, branch-free byte comparison for verifier checks. Plain
/// `==`/`listEquals` short-circuits on the first mismatch and leaks how much
/// of a guess was correct through timing.
bool constantTimeBytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
