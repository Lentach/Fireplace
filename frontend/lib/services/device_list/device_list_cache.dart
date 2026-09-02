// Client-side verified device-list cache (multi-device spec §5.2, Phase 2 T4
// stage C2) — the consumption point the T2 engine comment reserved for T4.
//
// The send path needs "which (userId, deviceId) addresses do I encrypt for"
// answered from DAK-SIGNED data only. This cache retains, per userId, the
// last list whose I7 chain verified (their TOFU'd IK → E → DAK → list →
// version), plus the highest version ever pinned so a served ROLLBACK stays
// detectable even after the cached entry is invalidated (falsification 3).
//
// Fail-closed by construction (falsification 9): nothing here ever invents a
// device list. A missing TOFU identity, a failed verification, or a rollback
// is an exception the caller must surface as a send failure — for an
// ENROLLED peer there is no honest degradation to "device 1 only". The ONLY
// single-device answer is the server's explicit `authorization: null`
// (no `account_authorizations` row — a non-enrolled account, single-device
// by construction: rows >= 2 are minted solely by the provisioning commit).

import 'device_authority_engine.dart';
import 'device_list_canonical.dart';
import 'sender_list_info.dart';

/// A device list the send path may trust.
class VerifiedDeviceList {
  const VerifiedDeviceList._({
    required this.enrolled,
    required this.version,
    required this.devices,
    this.listHash,
  });

  /// The verified view of an enrolled account.
  const VerifiedDeviceList.enrolled({
    required int version,
    required List<DeviceListEntry> devices,
    String? listHash,
  }) : this._(
         enrolled: true,
         version: version,
         devices: devices,
         listHash: listHash,
       );

  /// The server explicitly answered `authorization: null`: no enrollment row
  /// exists, so the account is single-device by construction. No version —
  /// a non-enrolled party carries no stamp on the wire (amendment (v)).
  const VerifiedDeviceList.notEnrolled()
    : this._(
        enrolled: false,
        version: null,
        devices: const [
          DeviceListEntry(deviceId: 1, platform: 'unknown', addedAtMs: 0),
        ],
      );

  final bool enrolled;

  /// DAK-signed list version, or null for a non-enrolled account.
  final int? version;

  final List<DeviceListEntry> devices;

  /// SHA-256 (base64) of the DAK-signed `listCanonical` bytes exactly as the
  /// server transported them — the value `senderListInfo` carries in-band
  /// (spec §12 amendment (xv)). Null for a non-enrolled account, which has no
  /// signed list to hash. Never recomputed from [devices]: a re-serialization
  /// would drift and produce phantom mismatches.
  final String? listHash;

  /// Devices a send must address: every entry not revoked.
  List<int> get liveDeviceIds => [
    for (final d in devices)
      if (d.revokedAtMs == null) d.deviceId,
  ];

  /// Is this device present in the list AND not revoked?
  ///
  /// The accept-side check of spec §12 amendments (e)/(xxvii): an inbound
  /// envelope whose origin device is absent-or-revoked here must not be
  /// decrypted, because revocation is bidirectional — a revoked device's
  /// ciphertext must not be accepted just because a session for it exists.
  ///
  /// A non-enrolled account verifies as the synthesized single device 1, so
  /// an inbound `originDeviceId >= 2` from one is correctly refused.
  bool isLiveDevice(int deviceId) =>
      devices.any((d) => d.deviceId == deviceId && d.revokedAtMs == null);
}

/// A device-list answer that failed verification. [reason] is the stable
/// code from [PeerDeviceListVerification] (`invalid_list_signature`,
/// `version_rollback`, …) or `no_tofu_identity` when there is no pinned key
/// to verify against.
class DeviceListVerificationException implements Exception {
  const DeviceListVerificationException(this.userId, this.reason);

  final int userId;
  final String reason;

  @override
  String toString() =>
      'DeviceListVerificationException(userId=$userId, reason=$reason)';
}

/// Per-account cache of verified lists. Pure state + verification — the
/// fetch round trip (emit/completer/timeout) lives with the socket owner.
class DeviceListCache {
  final Map<int, VerifiedDeviceList> _byUser = {};

  /// Highest verified version ever seen per userId. Deliberately NOT dropped
  /// by [invalidate]: rollback detection must survive cache invalidation, or
  /// a server could serve v1 again by first pushing a `deviceListChanged`.
  ///
  /// PERSISTED via [onPinAdvanced] (amendment (xlviii) clause 3). The argument
  /// above applies with more force to a process restart, which is a strictly
  /// stronger invalidation than [invalidate]: while this map was
  /// process-lifetime only, every app launch reopened the full rollback window,
  /// so a server could re-serve any older validly-signed list — one that
  /// re-admits a revoked device, or that downgrades a previously-enrolled peer
  /// to `authorization: null` and defeats the (xix) check at the top of
  /// [adopt], which reads exactly this map.
  final Map<int, int> _pinnedVersion = {};

  /// Fired when a pin ADVANCES, so the owner can persist it. Never fired for a
  /// no-change refresh.
  void Function(int userId, int version)? onPinAdvanced;

  /// Restore pins recorded by a previous process. Existing (higher) pins win —
  /// a seed must never LOWER a floor this process already established.
  void seedPins(Map<int, int> pins) {
    for (final entry in pins.entries) {
      final held = _pinnedVersion[entry.key];
      if (held == null || entry.value > held) {
        _pinnedVersion[entry.key] = entry.value;
      }
    }
  }

  /// The cached verified list, or null when a fetch is needed.
  VerifiedDeviceList? cached(int userId) => _byUser[userId];

  /// Highest version this client ever verified for [userId], or null.
  int? pinnedVersion(int userId) => _pinnedVersion[userId];

  /// Drop the cached entry so the next consumer refetches. The pinned
  /// version is retained (see [_pinnedVersion]).
  void invalidate(int userId) {
    _byUser.remove(userId);
  }

  /// Forget everything, pinned versions included — account switch only.
  void clear() {
    _byUser.clear();
    _pinnedVersion.clear();
  }

  /// Verifies a `getDeviceList`/`deviceListStale` answer along the I7 chain
  /// and adopts it into the cache.
  ///
  /// [authorization] is the wire map (`dakPub`, `enrollmentSig`,
  /// `enrollmentCreatedAt`, `listVersion`, `listSignature`, `listCanonical`)
  /// or null for a non-enrolled account. [tofuIdentityKeyBase64] is the
  /// TOFU-pinned identity of [userId] (own identity for self) — required for
  /// any non-null [authorization].
  ///
  /// Throws [DeviceListVerificationException] and caches NOTHING on any
  /// failure. Re-serving the already-pinned version is legitimate (a cache
  /// refresh that found no change); only a STRICTLY older version is a
  /// rollback.
  VerifiedDeviceList adopt({
    required int userId,
    required Map<String, dynamic>? authorization,
    required String? tofuIdentityKeyBase64,
  }) {
    if (authorization == null) {
      // Enrollment is DURABLE (spec §5.2: `account_authorizations` rows are
      // never removed), so enrolled → not-enrolled is never a legitimate
      // transition. Without this check a forged or stale `authorization: null`
      // for a party we already verified at version N would be cached as
      // "device 1 only" and silently NARROW the fan-out — dropping delivery to
      // that party's other devices, and (once the self-sync law of amendment
      // (xi) is live) silently killing self-sync to our own devices. It is the
      // same class of attack as a version rollback, so it is refused with the
      // same code and, like every other failure here, caches NOTHING.
      // Amendment (xix).
      if (_pinnedVersion[userId] != null) {
        throw DeviceListVerificationException(userId, 'version_rollback');
      }
      const list = VerifiedDeviceList.notEnrolled();
      _byUser[userId] = list;
      return list;
    }
    if (tofuIdentityKeyBase64 == null || tofuIdentityKeyBase64.isEmpty) {
      throw DeviceListVerificationException(userId, 'no_tofu_identity');
    }
    final pinned = _pinnedVersion[userId];
    final verification = DeviceAuthorityEngine.verifyPeerDeviceList(
      authorization: authorization,
      tofuIdentityKeyBase64: tofuIdentityKeyBase64,
      expectedUserId: userId,
      // The verifier rejects version <= previousVersion; equality with the
      // pinned version is a legitimate no-change refresh here, so shift the
      // floor by one: strictly-below-pinned still fails as version_rollback.
      previousVersion: pinned == null ? null : pinned - 1,
    );
    if (!verification.ok) {
      throw DeviceListVerificationException(
        userId,
        verification.reason ?? 'verification_failed',
      );
    }
    final deviceList = verification.deviceList!;
    // Hash what was TRANSPORTED and verified, not a re-encoding of it.
    final canonical = authorization['listCanonical'];
    final verified = VerifiedDeviceList.enrolled(
      version: deviceList.version,
      devices: deviceList.devices,
      listHash: canonical is String && canonical.isNotEmpty
          ? SenderListInfo.hashListCanonical(canonical)
          : null,
    );
    _byUser[userId] = verified;
    if (pinned == null || deviceList.version > pinned) {
      _pinnedVersion[userId] = deviceList.version;
      onPinAdvanced?.call(userId, deviceList.version);
    }
    return verified;
  }
}
