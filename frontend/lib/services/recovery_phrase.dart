import 'package:bip39_mnemonic/bip39_mnemonic.dart';

/// Recovery phrase generation and checking (multi-device spec §6.2.1).
///
/// The phrase is minted HERE, on the user's device, shown once, and sent to the
/// server only so it can store an Argon2id verifier. It is never written to
/// local storage: a phrase kept on the device would be lost by exactly the
/// event it exists to recover from.
///
/// BIP39 with its checksum is deliberate. A mistyped phrase is caught locally,
/// before it costs one of the few server-side attempts the lockout allows.
class RecoveryPhrase {
  const RecoveryPhrase._();

  /// 12 words from 128 bits of CSPRNG entropy (`Random.secure`), plus the
  /// 4-bit BIP39 checksum.
  static List<String> generate() =>
      Mnemonic.generate(Language.english, length: MnemonicLength.words12).words;

  /// Normalizes user input: lowercase, collapsed whitespace, trimmed. Typing a
  /// phrase back in is error-prone and none of that noise is meaningful.
  static String normalize(String input) =>
      input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Whether [input] is a well-formed 12-word English BIP39 phrase.
  ///
  /// Fails closed: an unknown word, the wrong length, or a bad checksum are all
  /// simply "not valid". This is a typo guard, never an authorization decision
  /// — only the server can decide whether a phrase is the account's.
  static bool isValid(String input) {
    final normalized = normalize(input);
    if (normalized.isEmpty) return false;
    if (normalized.split(' ').length != MnemonicLength.words12.words) {
      return false;
    }
    try {
      Mnemonic.fromSentence(normalized, Language.english);
      return true;
    } catch (_) {
      return false;
    }
  }
}
