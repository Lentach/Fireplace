import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_token_store.dart';

/// The CLEARTEXT enrolment hint (amendment (lxxvi) clause 1).
///
/// The passcode lock screen must choose between `passcodeEraseWarning` and
/// `passcodeEraseWarningEnrolled` — but it cannot read E2E state: on web the
/// store is wrapped while locked. So `EncryptionProvider` persists a plain
/// SharedPreferences bool `account_enrolled_hint_<uid>` from every explicit
/// `ownKeyBundleStatus.linkingEnabled` observation, and this util reads it
/// back with nothing but prefs (and, while locked, the stored access JWT to
/// name the account).
///
/// Deliberately cleartext, deliberately a HINT: it decides copy on the erase
/// panel, never security behaviour, so a stale or missing value costs one
/// slightly-wrong sentence and nothing more.
class AccountEnrolledHint {
  static String keyFor(int userId) => 'account_enrolled_hint_$userId';

  /// Best-effort persist; a prefs failure must never break the status path.
  static Future<void> write({
    required int userId,
    required bool enrolled,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyFor(userId), enrolled);
    } catch (_) {}
  }

  /// The hint for [userId], or for the last-logged-in account when null
  /// (the lock screen has no AuthProvider — the uid comes from the stored
  /// access JWT's `sub`, the same claim `AuthProvider` restores from; an
  /// EXPIRED token still names the account, so no validity check).
  /// False on every failure: the un-enrolled copy is the safe default.
  static Future<bool> read({int? userId, AuthTokenStore? tokens}) async {
    try {
      final uid = userId ?? await _lastLoggedInUserId(tokens ?? AuthTokenStore());
      if (uid == null) return false;
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(keyFor(uid)) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<int?> _lastLoggedInUserId(AuthTokenStore tokens) async {
    final stored = await tokens.read();
    final access = stored.access;
    if (access == null) return null;
    try {
      final sub = JwtDecoder.decode(access)['sub'];
      if (sub is num) return sub.toInt();
      return int.tryParse('$sub');
    } catch (_) {
      return null;
    }
  }
}
