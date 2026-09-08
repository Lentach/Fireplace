/// Seam between the link/restore adopt paths and the passcode key wrap
/// (amendment (lxxvi) clause 3).
///
/// `adoptProvisionedIdentity` / `adoptRestoredIdentity` land RAW key material
/// in the stores. On a device where wrapping is ON, a crash between that
/// write and the next unlock would leave keys raw on a "protected" device —
/// so the adopt paths call [run] as soon as the raw keys have landed, and
/// `PasscodeProvider` wires [afterRawKeysLanded] to its idempotent
/// `wrapRawKeysNow()` (a no-op with wrapping off or the vault locked).
///
/// A static seam rather than a provider lookup because the adopt paths run
/// inside `EncryptionService`, below the widget tree, with no BuildContext.
class PasscodeWrapHook {
  /// Set by `PasscodeProvider`; null until one exists (e.g. unit tests that
  /// never mount the provider), in which case [run] is a no-op.
  static Future<void> Function()? afterRawKeysLanded;

  static Future<void> run() async =>
      await (afterRawKeysLanded?.call() ?? Future<void>.value());
}
