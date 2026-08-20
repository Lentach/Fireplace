// §5.1 provisioning ceremony state machine (Phase 2 T3).
//
// Screen-scoped ChangeNotifier, deliberately NOT an 8th top-level provider
// (frontend/CLAUDE.md §2 pins exactly 7): DevicesScreen constructs one,
// registers it as ConnectionProvider's provisioning sink for its lifetime,
// and both link-flow screens drive the same instance.
//
// Two flows, one controller:
//  - PRIMARY (this device enrolled, DAK persisted): paste code → hello →
//    SAS → human approve → blob + signed v+1 list → wait for commit.
//  - NEW DEVICE (this device keyless): open → show OOB code → relayed hello
//    → SAS → blob → MAC-verify/decrypt → adopt identity → complete →
//    rebind session under the assigned deviceId → the EXISTING upload path
//    publishes the minted bundle/OTPs (amendment (b), option A).
//
// Abort hygiene (I1, falsification 18): every failure path of the new-device
// flow runs [_discardNewDeviceState], which deletes the adopted identity and
// every minted key through EncryptionService.discardProvisionedIdentity — N
// ends exactly as unkeyed as it started. The discard is a real enumerated
// delete, never a comment.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../device_list/device_authority_engine.dart';
import '../device_list/device_list_canonical.dart';
import '../encryption_service.dart';
import 'dak_store.dart';
import 'link_crypto.dart';

/// Server events ConnectionProvider forwards to the registered ceremony
/// controller. One interface so the provider stays a dumb router.
abstract class ProvisioningEventSink {
  void onProvisioningOpened(dynamic data);
  void onProvisioningHelloAck(dynamic data);
  void onProvisioningHelloRelay(dynamic data);
  void onProvisionDeviceAck(dynamic data);
  void onProvisioningBlob(dynamic data);
  void onProvisioningCompleted(dynamic data);
  void onProvisioningCancelled(dynamic data);
  void onDeviceAuthorityEnrolled(dynamic data);
  void onDeviceList(dynamic data);
  void onDeviceListChanged(dynamic data);
}

/// The narrow identity surface the ceremony needs. Production wraps
/// [EncryptionService]; tests fake it.
abstract class LinkIdentityGateway {
  /// base64 of the own serialized identity public key, or null when this
  /// device holds no identity.
  Future<String?> ownIdentityPublicKeyBase64();

  /// The full identity pair (primary side, blob building). READ ONLY.
  Future<dynamic> ownIdentityKeyPair();

  Future<void> adoptProvisionedIdentity({
    required int userId,
    required String ikPubBase64,
    required String ikPrivBase64,
    required String dakPubBase64,
  });

  Future<void> discardProvisionedIdentity(int userId);
}

/// Production gateway over the app's one EncryptionService instance.
class EncryptionServiceLinkGateway implements LinkIdentityGateway {
  EncryptionServiceLinkGateway(this._service);

  final EncryptionService _service;

  @override
  Future<String?> ownIdentityPublicKeyBase64() =>
      _service.currentIdentityPublicKeyBase64();

  @override
  Future<dynamic> ownIdentityKeyPair() => _service.identityKeyPairForLinking();

  @override
  Future<void> adoptProvisionedIdentity({
    required int userId,
    required String ikPubBase64,
    required String ikPrivBase64,
    required String dakPubBase64,
  }) => _service.adoptProvisionedIdentity(
    userId: userId,
    ikPubBase64: ikPubBase64,
    ikPrivBase64: ikPrivBase64,
    dakPubBase64: dakPubBase64,
  );

  @override
  Future<void> discardProvisionedIdentity(int userId) =>
      _service.discardProvisionedIdentity(userId);
}

/// Where the devices surface stands for THIS device/account.
enum DeviceListState { loading, notEnrolled, enrolled, chainInvalid }

/// Primary-flow steps, in ceremony order.
enum PrimaryLinkStep {
  idle,
  awaitingHelloAck,
  showSas,
  staging,
  waitingForDevice,
  done,
  failed,
}

/// New-device-flow steps, in ceremony order.
enum NewDeviceLinkStep {
  idle,
  opening,
  showCode,
  showSas,
  completing,
  rebinding,
  done,
  aborted,
}

class LinkCeremonyController extends ChangeNotifier
    implements ProvisioningEventSink {
  LinkCeremonyController({
    required this.userId,
    required void Function(String event, dynamic data) emit,
    required LinkIdentityGateway identity,
    required Future<void> Function(Map<String, dynamic> tokens) adoptSession,
    required Future<void> Function(String accessToken) reconnect,
    DakStore? dakStore,
    DeviceAuthorityEngine? engine,
  }) : _emit = emit,
       _identity = identity,
       _adoptSession = adoptSession,
       _reconnect = reconnect,
       _dakStore = dakStore ?? DakStore(),
       _engine = engine ?? DeviceAuthorityEngine();

  final int userId;
  final void Function(String event, dynamic data) _emit;
  final LinkIdentityGateway _identity;
  final Future<void> Function(Map<String, dynamic> tokens) _adoptSession;
  final Future<void> Function(String accessToken) _reconnect;
  final DakStore _dakStore;
  final DeviceAuthorityEngine _engine;

  static const int _kResignRetryCap = 3;

  // ---------- Devices surface ----------

  DeviceListState listState = DeviceListState.loading;
  DeviceList? verifiedList;
  String? listFailureReason;

  /// The raw authorization fields of the last VERIFIED own-list answer —
  /// the primary flow signs against these.
  Map<String, dynamic>? _authorization;

  /// Enable-linking outcome the UI renders (`already_enrolled` is a DISTINCT
  /// state: another install of this account beat us to the authority).
  String? enrollError;
  bool enrolling = false;

  // ---------- Primary flow ----------

  PrimaryLinkStep primaryStep = PrimaryLinkStep.idle;
  String? primaryError;
  String? primarySas;
  int? assignedDeviceId;
  LinkOobCode? _parsedCode;
  dynamic _ephP; // ECKeyPair — dynamic to keep the gateway seam narrow
  Uint8List? _ephPubP;
  String? _primaryProvisioningId;
  int _resignRetries = 0;
  bool _resignPending = false;

  // ---------- New-device flow ----------

  NewDeviceLinkStep newDeviceStep = NewDeviceLinkStep.idle;
  String? newDeviceError;
  String? newDeviceSas;
  String? oobCode;
  String? _openProvisioningId;
  Uint8List? _ephPubNBytes;
  dynamic _ephN;
  Uint8List? _relayedEphPubP;
  String _platform = 'web';
  Timer? _expiryTimer;
  bool _identityAdopted = false;

  // ---------- Devices list ----------

  void refreshDeviceList() {
    _emit('getDeviceList', {'userId': userId});
  }

  @override
  void onDeviceList(dynamic data) {
    if (data is! Map || data['userId'] != userId) return;
    final authorization = data['authorization'];
    if (authorization == null) {
      listState = DeviceListState.notEnrolled;
      verifiedList = null;
      _authorization = null;
      notifyListeners();
      return;
    }
    if (authorization is! Map) return;
    _verifyOwnList(authorization.cast<String, dynamic>());
  }

  Future<void> _verifyOwnList(Map<String, dynamic> authorization) async {
    // The own list is verified with the SAME I7 chain semantics a peer uses,
    // against this device's own TOFU'd identity — the server's word alone is
    // never trusted for list content.
    final tofu = await _identity.ownIdentityPublicKeyBase64();
    if (tofu == null) {
      // Keyless device (new-device flow candidate): render the list fields
      // unverified is NOT an option — mark the chain unverifiable.
      listState = DeviceListState.chainInvalid;
      listFailureReason = 'no_local_identity';
      _authorization = null;
      notifyListeners();
      return;
    }
    final result = DeviceAuthorityEngine.verifyPeerDeviceList(
      authorization: authorization,
      tofuIdentityKeyBase64: tofu,
      expectedUserId: userId,
    );
    if (!result.ok) {
      listState = DeviceListState.chainInvalid;
      listFailureReason = result.reason;
      _authorization = null;
    } else {
      listState = DeviceListState.enrolled;
      verifiedList = result.deviceList;
      listFailureReason = null;
      _authorization = authorization;
      if (primaryStep == PrimaryLinkStep.waitingForDevice &&
          assignedDeviceId != null &&
          result.deviceList!.devices.any(
            (d) => d.deviceId == assignedDeviceId,
          )) {
        primaryStep = PrimaryLinkStep.done;
      }
      if (_resignPending) {
        _resignPending = false;
        unawaited(_stageProvisionDevice());
      }
    }
    notifyListeners();
  }

  @override
  void onDeviceListChanged(dynamic data) {
    if (data is! Map || data['userId'] != userId) return;
    refreshDeviceList();
  }

  // ---------- Enable linking (primary enrollment) ----------

  /// Rider order (T3): mint → persist DAK armed → ONLY THEN emit enroll.
  Future<void> enableLinking({required String platform}) async {
    if (enrolling) return;
    enrolling = true;
    enrollError = null;
    notifyListeners();
    try {
      final identity = await _identity.ownIdentityKeyPair();
      final payload = _engine.mintEnrollment(
        userId: userId,
        // The gateway returns the service's IdentityKeyPair; the engine's
        // parameter type enforces it.
        identity: identity,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        platform: platform,
      );
      final exported = _engine.exportDakForPersistence();
      await _dakStore.persistArmed(
        DakRecord(
          userId: userId,
          dakPub: exported['dakPub']!,
          dakPriv: exported['dakPriv']!,
          createdAtMs: payload['createdAt'] as int,
        ),
      );
      _emit('enrollDeviceAuthority', payload);
    } catch (e) {
      enrollError = 'enroll_failed';
      enrolling = false;
      notifyListeners();
    }
  }

  @override
  void onDeviceAuthorityEnrolled(dynamic data) {
    enrolling = false;
    if (data is Map && data['success'] == true) {
      enrollError = null;
      refreshDeviceList();
    } else {
      enrollError = data is Map && data['error'] is String
          ? data['error'] as String
          : 'enroll_failed';
      if (enrollError == 'already_enrolled') {
        // Another install already holds the authority — the persisted DAK
        // here authorizes nothing and keeping it invites signing lists the
        // server never pinned an E for.
        unawaited(_dakStore.clear(userId: userId));
      }
      notifyListeners();
    }
  }

  // ---------- Primary flow ----------

  /// Manual paste is the REQUIRED OOB path (spec item (i)).
  Future<void> startPrimaryFlow(String rawCode) async {
    final code = LinkOobCode.tryParse(rawCode.trim());
    if (code == null) {
      primaryError = 'invalid_code';
      primaryStep = PrimaryLinkStep.failed;
      notifyListeners();
      return;
    }
    final dak = await _readDak();
    if (dak == null) {
      primaryError = 'no_dak';
      primaryStep = PrimaryLinkStep.failed;
      notifyListeners();
      return;
    }
    _parsedCode = code;
    _primaryProvisioningId = code.provisioningId;
    final eph = generateLinkEphemeral();
    _ephP = eph;
    _ephPubP = linkEphemeralPublicBytes(eph);
    primaryError = null;
    primarySas = null;
    assignedDeviceId = null;
    _resignRetries = 0;
    primaryStep = PrimaryLinkStep.awaitingHelloAck;
    notifyListeners();
    _emit('provisioningHello', {
      'provisioningId': code.provisioningId,
      'ephPubP': base64Encode(_ephPubP!),
    });
  }

  Future<DakRecord?> _readDak() async {
    try {
      final record = await _dakStore.read(userId: userId);
      if (record != null) {
        _engine.restoreDak(
          dakPubBase64: record.dakPub,
          dakPrivBase64: record.dakPriv,
        );
      }
      return record;
    } catch (_) {
      return null;
    }
  }

  @override
  void onProvisioningHelloAck(dynamic data) {
    if (primaryStep != PrimaryLinkStep.awaitingHelloAck) return;
    if (data is! Map || data['success'] != true || data['deviceId'] is! int) {
      primaryError = data is Map && data['error'] is String
          ? data['error'] as String
          : 'hello_failed';
      primaryStep = PrimaryLinkStep.failed;
      notifyListeners();
      return;
    }
    final code = _parsedCode;
    final eph = _ephP;
    if (code == null || eph == null) return;
    assignedDeviceId = data['deviceId'] as int;
    final transcript = linkTranscript(
      provisioningId: code.provisioningId,
      ephPubN: code.ephPubN,
      ephPubP: _ephPubP!,
    );
    final sharedSecret = linkSharedSecret(
      theirEphPub: code.ephPubN,
      // ignore: avoid_dynamic_calls
      ownEphPriv: eph.privateKey,
    );
    primarySas = deriveLinkSas(
      sharedSecret: sharedSecret,
      transcript: transcript,
    );
    primaryStep = PrimaryLinkStep.showSas;
    notifyListeners();
  }

  /// The human compared both screens and approved: NOW (and only now —
  /// secrets-last, I3) the IK-bearing blob is built and staged.
  Future<void> approvePrimary() async {
    if (primaryStep != PrimaryLinkStep.showSas) return;
    primaryStep = PrimaryLinkStep.staging;
    notifyListeners();
    await _stageProvisionDevice();
  }

  Future<void> _stageProvisionDevice() async {
    final code = _parsedCode;
    final eph = _ephP;
    final deviceId = assignedDeviceId;
    final authorization = _authorization;
    final list = verifiedList;
    if (code == null || eph == null || deviceId == null) return;
    if (authorization == null || list == null) {
      primaryError = 'list_unavailable';
      primaryStep = PrimaryLinkStep.failed;
      notifyListeners();
      return;
    }
    try {
      final identity = await _identity.ownIdentityKeyPair();
      final transcript = linkTranscript(
        provisioningId: code.provisioningId,
        ephPubN: code.ephPubN,
        ephPubP: _ephPubP!,
      );
      final sharedSecret = linkSharedSecret(
        theirEphPub: code.ephPubN,
        // ignore: avoid_dynamic_calls
        ownEphPriv: eph.privateKey,
      );
      final keys = deriveLinkBlobKeys(
        sharedSecret: sharedSecret,
        transcript: transcript,
      );
      final blob = sealLinkBlob(
        keys: keys,
        payload: LinkBlobPayload(
          userId: userId,
          deviceId: deviceId,
          // ignore: avoid_dynamic_calls
          ikPub: base64Encode(identity.getPublicKey().serialize() as List<int>),
          // ignore: avoid_dynamic_calls
          ikPriv: base64Encode(identity.getPrivateKey().serialize() as List<int>),
          dakPub: _authorization!['dakPub'] as String,
          enrollmentCreatedAt: _authorization!['enrollmentCreatedAt'] as int,
          enrollmentSig: _authorization!['enrollmentSig'] as String,
        ),
      );
      // The staged v+1 list: current entries + EXACTLY the assigned device,
      // platform from the code, NO name (amendment (i)).
      final staged = DeviceList(
        userId: userId,
        version: list.version + 1,
        devices: [
          ...list.devices,
          DeviceListEntry(
            deviceId: deviceId,
            platform: code.platform,
            addedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        ],
      );
      final signed = _engine.signList(staged);
      _emit('provisionDevice', {
        'provisioningId': code.provisioningId,
        'blob': base64Encode(blob),
        'listCanonical': signed['listCanonical'],
        'listSignature': signed['listSignature'],
      });
    } catch (e) {
      primaryError = 'stage_failed';
      primaryStep = PrimaryLinkStep.failed;
      notifyListeners();
    }
  }

  @override
  void onProvisionDeviceAck(dynamic data) {
    if (primaryStep != PrimaryLinkStep.staging) return;
    if (data is Map && data['success'] == true) {
      primaryStep = PrimaryLinkStep.waitingForDevice;
      notifyListeners();
      return;
    }
    final error = data is Map && data['error'] is String
        ? data['error'] as String
        : 'stage_failed';
    if (error == 'stale_version' && _resignRetries < _kResignRetryCap) {
      // Falsification 20: a concurrent ceremony took the version slot —
      // refetch the committed list and re-sign v+2 against the SAME stage.
      _resignRetries++;
      _resignPending = true;
      refreshDeviceList();
      return;
    }
    primaryError = error;
    primaryStep = PrimaryLinkStep.failed;
    notifyListeners();
  }

  void cancelPrimary() {
    final id = _primaryProvisioningId;
    if (id != null &&
        primaryStep != PrimaryLinkStep.idle &&
        primaryStep != PrimaryLinkStep.done) {
      _emit('cancelProvisioning', {'provisioningId': id});
    }
    _resetPrimary();
    notifyListeners();
  }

  void _resetPrimary() {
    primaryStep = PrimaryLinkStep.idle;
    primaryError = null;
    primarySas = null;
    assignedDeviceId = null;
    _parsedCode = null;
    _ephP = null;
    _ephPubP = null;
    _primaryProvisioningId = null;
    _resignRetries = 0;
    _resignPending = false;
  }

  // ---------- New-device flow ----------

  Future<void> startNewDeviceFlow({required String platform}) async {
    _platform = platform;
    final eph = generateLinkEphemeral();
    _ephN = eph;
    _ephPubNBytes = linkEphemeralPublicBytes(eph);
    newDeviceError = null;
    newDeviceSas = null;
    oobCode = null;
    _relayedEphPubP = null;
    _identityAdopted = false;
    newDeviceStep = NewDeviceLinkStep.opening;
    notifyListeners();
    _emit('openProvisioning', <String, dynamic>{});
  }

  @override
  void onProvisioningOpened(dynamic data) {
    if (newDeviceStep != NewDeviceLinkStep.opening) return;
    if (data is! Map || data['success'] != true) {
      newDeviceError = data is Map && data['error'] is String
          ? data['error'] as String
          : 'open_failed';
      newDeviceStep = NewDeviceLinkStep.aborted;
      notifyListeners();
      return;
    }
    final id = data['provisioningId'];
    final expiresAt = data['expiresAt'];
    if (id is! String || _ephPubNBytes == null) return;
    _openProvisioningId = id;
    oobCode = LinkOobCode(
      provisioningId: id,
      ephPubN: _ephPubNBytes!,
      platform: _platform,
    ).encode();
    newDeviceStep = NewDeviceLinkStep.showCode;
    if (expiresAt is int) {
      final remaining = DateTime.fromMillisecondsSinceEpoch(
        expiresAt,
      ).difference(DateTime.now());
      _expiryTimer?.cancel();
      if (remaining > Duration.zero) {
        _expiryTimer = Timer(remaining, () {
          // TTL expiry: the server forgot the stage (falsification 18's
          // boundary) — discard everything and end as unkeyed as we began.
          unawaited(abortNewDevice('expired'));
        });
      }
    }
    notifyListeners();
  }

  @override
  void onProvisioningHelloRelay(dynamic data) {
    if (data is! Map ||
        data['provisioningId'] != _openProvisioningId ||
        data['ephPubP'] is! String) {
      return;
    }
    if (newDeviceStep != NewDeviceLinkStep.showCode &&
        newDeviceStep != NewDeviceLinkStep.showSas) {
      return;
    }
    final Uint8List ephPubP;
    try {
      ephPubP = base64Decode(data['ephPubP'] as String);
    } catch (_) {
      return;
    }
    if (ephPubP.length != kLinkEphemeralPublicKeyLength) return;
    _relayedEphPubP = ephPubP;
    final transcript = linkTranscript(
      provisioningId: _openProvisioningId!,
      ephPubN: _ephPubNBytes!,
      ephPubP: ephPubP,
    );
    final sharedSecret = linkSharedSecret(
      theirEphPub: ephPubP,
      // ignore: avoid_dynamic_calls
      ownEphPriv: _ephN.privateKey,
    );
    newDeviceSas = deriveLinkSas(
      sharedSecret: sharedSecret,
      transcript: transcript,
    );
    newDeviceStep = NewDeviceLinkStep.showSas;
    notifyListeners();
  }

  @override
  void onProvisioningBlob(dynamic data) {
    if (data is! Map || data['provisioningId'] != _openProvisioningId) return;
    final blobB64 = data['blob'];
    if (blobB64 is! String) return;
    final ephPubP = _relayedEphPubP;
    if (ephPubP == null ||
        (newDeviceStep != NewDeviceLinkStep.showSas &&
            newDeviceStep != NewDeviceLinkStep.completing)) {
      return;
    }
    unawaited(_handleBlob(blobB64, ephPubP));
  }

  Future<void> _handleBlob(String blobB64, Uint8List ephPubP) async {
    try {
      final transcript = linkTranscript(
        provisioningId: _openProvisioningId!,
        ephPubN: _ephPubNBytes!,
        ephPubP: ephPubP,
      );
      final sharedSecret = linkSharedSecret(
        theirEphPub: ephPubP,
        // ignore: avoid_dynamic_calls
        ownEphPriv: _ephN.privateKey,
      );
      final keys = deriveLinkBlobKeys(
        sharedSecret: sharedSecret,
        transcript: transcript,
      );
      // MAC verified constant-time BEFORE decrypt inside openLinkBlob.
      final payload = openLinkBlob(
        keys: keys,
        blob: base64Decode(blobB64),
      );
      if (payload.userId != userId) {
        await abortNewDevice('blob_user_mismatch');
        return;
      }
      await _identity.adoptProvisionedIdentity(
        userId: userId,
        ikPubBase64: payload.ikPub,
        ikPrivBase64: payload.ikPriv,
        dakPubBase64: payload.dakPub,
      );
      _identityAdopted = true;
      newDeviceStep = NewDeviceLinkStep.completing;
      notifyListeners();
      _emit('provisioningComplete', {
        'provisioningId': _openProvisioningId,
      });
    } on LinkBlobException catch (e) {
      await abortNewDevice(e.reason);
    } catch (_) {
      await abortNewDevice('adopt_failed');
    }
  }

  @override
  void onProvisioningCompleted(dynamic data) {
    if (newDeviceStep != NewDeviceLinkStep.completing) return;
    if (data is! Map) return;
    if (data['success'] == true) {
      unawaited(_finishRebind(data.cast<String, dynamic>()));
      return;
    }
    final error = data['error'];
    if (error == 'stale_version') {
      // The primary lost a concurrent version race and will re-sign and
      // re-stage against this SAME stage; the next provisioningBlob re-runs
      // the adopt (same identity bytes) and re-emits complete.
      return;
    }
    unawaited(abortNewDevice(error is String ? error : 'complete_failed'));
  }

  Future<void> _finishRebind(Map<String, dynamic> data) async {
    _expiryTimer?.cancel();
    final access = data['access_token'];
    final refresh = data['refresh_token'];
    if (access is! String || refresh is! String) {
      await abortNewDevice('complete_failed');
      return;
    }
    newDeviceStep = NewDeviceLinkStep.rebinding;
    notifyListeners();
    try {
      // Amendment (iii): persist the deviceId-bound session, then disconnect/
      // reconnect under it. Only THEN does the existing OTP-gated upload path
      // publish the minted bundle+OTPs (amendment (b): a bundle uploaded
      // before rebind would land on device 1 and overwrite the primary's).
      await _adoptSession({'access_token': access, 'refresh_token': refresh});
      await _reconnect(access);
      newDeviceStep = NewDeviceLinkStep.done;
      notifyListeners();
    } catch (_) {
      // Session adoption failed AFTER the server committed the device. The
      // identity is real and committed — discarding it now would orphan the
      // devices row; surface the failure instead.
      newDeviceError = 'rebind_failed';
      newDeviceStep = NewDeviceLinkStep.aborted;
      notifyListeners();
    }
  }

  @override
  void onProvisioningCancelled(dynamic data) {
    if (data is! Map) return;
    // The caller-ack shape carries `success`; the opener notification is the
    // bare `{provisioningId}` push — only the latter aborts this flow.
    if (data['success'] != null) return;
    if (data['provisioningId'] != _openProvisioningId) return;
    if (newDeviceStep == NewDeviceLinkStep.idle ||
        newDeviceStep == NewDeviceLinkStep.done) {
      return;
    }
    unawaited(abortNewDevice('cancelled'));
  }

  /// I1 abort hygiene: discard the adopted identity, every minted key, the
  /// stored dakPub and the assigned id — then reset the flow.
  Future<void> abortNewDevice(String reason) async {
    _expiryTimer?.cancel();
    final id = _openProvisioningId;
    if (reason != 'expired' && reason != 'cancelled' && id != null) {
      _emit('cancelProvisioning', {'provisioningId': id});
    }
    if (_identityAdopted) {
      try {
        await _identity.discardProvisionedIdentity(userId);
      } catch (_) {
        // The discard failing must not mask the abort itself; the adopt
        // path re-runs it before any retry.
      }
      _identityAdopted = false;
    }
    _openProvisioningId = null;
    _ephN = null;
    _ephPubNBytes = null;
    _relayedEphPubP = null;
    oobCode = null;
    newDeviceSas = null;
    newDeviceError = reason;
    newDeviceStep = NewDeviceLinkStep.aborted;
    notifyListeners();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}
