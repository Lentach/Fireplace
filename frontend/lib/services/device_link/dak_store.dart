// DAK persistence (Phase 2 T3 rider on T2: the DeviceAuthorityEngine keeps
// the minted DAK in memory only — this store is its Keystore-backed home).
//
// ONE atomic JSON record per account, through the SAME DualStorage seam the
// Signal keys use (flutter_secure_storage on mobile, the sealed/'sig_'
// SharedPreferencesAsync path on web) — a second storage convention would be
// a second place keys silently die. The record is armed before it is
// trusted: write, then read back in a FRESH call, and only a verified
// read-back counts as persisted (the content_key_manager discipline; the
// enable-linking flow must not emit the enrollment before the DAK provably
// survives a round trip — a pinned E whose private half was never persisted
// would dead-end the account's device authority until a §6.2 reset).

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../encryption/signal_stores.dart';

/// The persisted device-authority keypair of THIS device (primary only —
/// a linked device never holds a DAK private half, invariant I2).
class DakRecord {
  const DakRecord({
    required this.userId,
    required this.dakPub,
    required this.dakPriv,
    required this.createdAtMs,
  });

  /// base64 — 33-byte serialized public key.
  final String dakPub;

  /// base64 — 32-byte serialized private key. Never leaves this store.
  final String dakPriv;

  final int userId;
  final int createdAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'userId': userId,
    'dakPub': dakPub,
    'dakPriv': dakPriv,
    'createdAtMs': createdAtMs,
  };

  static DakRecord? _fromJson(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final userId = decoded['userId'];
    final dakPub = decoded['dakPub'];
    final dakPriv = decoded['dakPriv'];
    final createdAtMs = decoded['createdAtMs'];
    if (userId is! int ||
        dakPub is! String ||
        dakPriv is! String ||
        createdAtMs is! int) {
      return null;
    }
    return DakRecord(
      userId: userId,
      dakPub: dakPub,
      dakPriv: dakPriv,
      createdAtMs: createdAtMs,
    );
  }

  bool _sameAs(DakRecord other) =>
      userId == other.userId &&
      dakPub == other.dakPub &&
      dakPriv == other.dakPriv &&
      createdAtMs == other.createdAtMs;
}

/// Keystore-backed DAK record store.
class DakStore {
  /// [storage] is a test seam; production uses the same DualStorage
  /// construction as the Signal stores.
  DakStore({DualStorage? storage})
    : _storage = storage ?? DualStorage(const FlutterSecureStorage());

  final DualStorage _storage;

  static String _key(int userId) => 'dak_record_v1_$userId';

  /// The stored record, or null when this device holds no DAK. A record that
  /// exists but cannot be parsed is DAMAGE, not absence — it throws, because
  /// treating it as absent would invite minting a second DAK the server's
  /// first-write-wins enrollment will refuse forever.
  Future<DakRecord?> read({required int userId}) async {
    final raw = await _storage.read(key: _key(userId));
    if (raw == null) return null;
    final DakRecord? record;
    try {
      record = DakRecord._fromJson(jsonDecode(raw));
    } catch (_) {
      throw StateError('dak record unreadable for user $userId');
    }
    if (record == null) {
      throw StateError('dak record unreadable for user $userId');
    }
    return record;
  }

  /// ARMED write: persist, then read back in a fresh call and verify every
  /// field. Throws [StateError] when the read-back does not prove the write;
  /// callers MUST NOT emit the enrollment until this returns.
  Future<void> persistArmed(DakRecord record) async {
    await _storage.write(
      key: _key(record.userId),
      value: jsonEncode(record),
    );
    final readBack = await read(userId: record.userId);
    if (readBack == null || !readBack._sameAs(record)) {
      throw StateError('dak record failed read-back verification');
    }
  }

  /// Removes the record (abort hygiene / account teardown).
  Future<void> clear({required int userId}) =>
      _storage.delete(key: _key(userId));
}
