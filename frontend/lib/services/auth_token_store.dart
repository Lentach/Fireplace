import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/e2e_persistent_diag.dart';
import 'secure_kv.dart';

/// Where the JWT + refresh token live at rest.
///
/// Web AND non-Android hosts (desktop dev, the flutter_test VM): plain
/// SharedPreferences, exactly the historical behavior — on web,
/// flutter_secure_storage's backing loses data when tabs close, which is
/// disqualifying for the token that keeps a session alive; and the only
/// shipped native platform is the Android APK.
///
/// Native: flutter_secure_storage. The refresh token is a long-lived bearer
/// credential; in the plaintext prefs XML it was readable at rest by anyone
/// with the device image (issue #105 inventory item 7). A one-time migration
/// moves tokens out of prefs, gated the same way every migration here is:
/// copy, VERIFY by fresh read-back, and only then delete the prefs copy — a
/// failed secure write must leave the working tokens where they were, because
/// "logged out on next launch" is a real cost and prefs is merely the status
/// quo, not a regression.
///
/// Failure honesty (0.1.11, handoff §5.4): a broken store used to read as
/// "no tokens" — the error-as-absence inversion that manufactures a permanent
/// logout out of a transient storage hiccup (the app then DELETED the intact
/// token it believed absent). [read] now retries briefly and, if storage still
/// answers with errors, reports `readFailed: true` — a state the caller MUST
/// treat as "do not decide", never as logged-out. Failed writes are recorded
/// durably so a "logged out next boot" finally has a paper trail.
class AuthTokenStore {
  AuthTokenStore({SecureKv? secure, bool? useSecureStorage})
    : _secure = secure ?? const FlutterSecureStorageKv(FlutterSecureStorage()),
      _useSecure = useSecureStorage ?? (!kIsWeb && Platform.isAndroid);

  final SecureKv _secure;

  /// Same platform rule as the content-store opener: secure storage on real
  /// Android only. Overridable so tests can drive the native path with a
  /// fake [SecureKv] on any host.
  final bool _useSecure;

  static const String _accessKey = 'jwt_token';
  static const String _refreshKey = 'refresh_token';

  /// Retry cadence for [read]: storage plugins fail transiently (Android
  /// Keystore after OS updates/backup restores; browser storage under early
  /// boot contention). Three quick attempts before conceding.
  static const List<Duration> _readRetryDelays = [
    Duration(milliseconds: 150),
    Duration(milliseconds: 400),
  ];

  /// `readFailed: true` means storage ERRORED on every attempt — the tokens
  /// may well exist. Callers MUST NOT treat that as "logged out" and MUST NOT
  /// clear anything in response.
  Future<({String? access, String? refresh, bool readFailed})> read() async {
    Object? lastError;
    for (var attempt = 0; attempt <= _readRetryDelays.length; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_readRetryDelays[attempt - 1]);
      }
      try {
        final r = await _readOnce();
        return (access: r.access, refresh: r.refresh, readFailed: false);
      } catch (e) {
        lastError = e;
      }
    }
    E2ePersistentDiag.record('AUTH_TOKENS_UNREADABLE', {
      'errorType': lastError.runtimeType.toString(),
      'platform': _useSecure ? 'secure' : 'prefs',
    });
    return (access: null, refresh: null, readFailed: true);
  }

  Future<({String? access, String? refresh})> _readOnce() async {
    if (!_useSecure) {
      final prefs = await SharedPreferences.getInstance();
      return (
        access: prefs.getString(_accessKey),
        refresh: prefs.getString(_refreshKey),
      );
    }
    var access = await _secure.read(_accessKey);
    var refresh = await _secure.read(_refreshKey);
    if (access == null && refresh == null) {
      final migrated = await _migrateFromPrefs();
      access = migrated.access;
      refresh = migrated.refresh;
    } else {
      // Tokens already secure: any prefs copy is residue from the
      // pre-migration build. Best-effort cleanup, never gating (it catches
      // internally, so it cannot fail this read).
      await _removePrefsCopies();
    }
    return (access: access, refresh: refresh);
  }

  Future<void> write({required String access, required String refresh}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _writeOnce(access, refresh);
        return;
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
    }
    // A refused write costs a re-login on the next cold start; the session in
    // memory is unaffected. It used to also be INVISIBLE — record it so the
    // next "logged out overnight" dump explains itself.
    E2ePersistentDiag.record('AUTH_TOKEN_WRITE_FAILED', {
      'platform': _useSecure ? 'secure' : 'prefs',
    });
  }

  Future<void> _writeOnce(String access, String refresh) async {
    if (!_useSecure) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accessKey, access);
      await prefs.setString(_refreshKey, refresh);
      return;
    }
    await _secure.write(_accessKey, access);
    await _secure.write(_refreshKey, refresh);
    await _removePrefsCopies();
  }

  Future<void> clear() async {
    if (!_useSecure) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_accessKey);
        await prefs.remove(_refreshKey);
      } catch (_) {}
      return;
    }
    try {
      await _secure.delete(_accessKey);
      await _secure.delete(_refreshKey);
    } catch (_) {}
    await _removePrefsCopies();
  }

  /// One-time move of a pre-Phase-2 install's tokens into secure storage.
  /// Copy -> fresh read-back -> only then remove from prefs.
  Future<({String? access, String? refresh})> _migrateFromPrefs() async {
    String? access;
    String? refresh;
    try {
      final prefs = await SharedPreferences.getInstance();
      access = prefs.getString(_accessKey);
      refresh = prefs.getString(_refreshKey);
      if (access == null && refresh == null) {
        return (access: null, refresh: null);
      }
      var verified = true;
      if (access != null) {
        await _secure.write(_accessKey, access);
        verified &= await _secure.read(_accessKey) == access;
      }
      if (refresh != null) {
        await _secure.write(_refreshKey, refresh);
        verified &= await _secure.read(_refreshKey) == refresh;
      }
      if (!verified) {
        // The secure copy is not proven; the prefs copy stays the working
        // set. Serve it so this launch still logs in.
        return (access: access, refresh: refresh);
      }
      await prefs.remove(_accessKey);
      await prefs.remove(_refreshKey);
      return (access: access, refresh: refresh);
    } catch (_) {
      return (access: access, refresh: refresh);
    }
  }

  Future<void> _removePrefsCopies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_accessKey)) await prefs.remove(_accessKey);
      if (prefs.containsKey(_refreshKey)) await prefs.remove(_refreshKey);
    } catch (_) {}
  }
}
