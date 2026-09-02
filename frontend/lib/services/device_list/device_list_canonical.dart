// Canonical device-list bytes (multi-device spec §3, Phase 2 T2).
//
// The signed device list is `{ userId, version, devices: [...] }` serialized
// to ONE canonical byte string: JSON with no whitespace, `userId` and
// `version` first, every other object's keys sorted, integers only for
// version/timestamps, control characters rejected. The DAK signature and
// `listHash` are computed over these bytes VERBATIM, and the bytes travel as
// opaque base64 everywhere (§3 transport rule) — nothing may parse and
// re-serialize them in transit.
//
// The parser is deliberately strict the falsification-23 way: it structurally
// validates, then RE-ENCODES canonically and compares byte-for-byte with the
// input. Any liberal JSON the writer could never have produced — duplicate
// keys (jsonDecode keeps the last, so the re-encode is shorter), whitespace,
// reordered keys, `1.0`/`1e3` number forms, `\u0041` escapes — fails that
// comparison and is rejected AT PARSE.
//
// NFC note: the server (the storage gate) additionally rejects a `name` that
// is not NFC-normalized (Node `String.normalize`). Dart core ships no Unicode
// normalizer, and normalization is display hygiene, not a signature-ambiguity
// risk here — the signature binds the exact bytes, and this parser's
// byte-exact rule already rejects every re-encoding of the same list. When T3
// lands the rename UI (the first writer of non-trivial names), the client-side
// NFC normalization lands with it.
//
// Pure Dart on purpose: shared by lib code, the widget-test suite, the wire
// harness, and `tool/device_list_vector_generator.dart` (run via `dart run`).

import 'dart:convert';
import 'dart:typed_data';

/// Upper bound on `name` length (UTF-16 code units). Spec §3: length-capped.
const int kDeviceNameMaxLength = 64;

/// Upper bound on `platform` length (UTF-16 code units).
const int kDevicePlatformMaxLength = 32;

/// Generous bound on the devices array: the ratified live cap is 3 devices,
/// but revoked entries stay on the list, so leave room without allowing an
/// unbounded payload.
const int kDeviceListMaxEntries = 64;

/// One device row of the signed list (spec §3).
class DeviceListEntry {
  const DeviceListEntry({
    required this.deviceId,
    required this.platform,
    required this.addedAtMs,
    this.name,
    this.revokedAtMs,
  });

  final int deviceId;
  final String platform;
  final int addedAtMs;
  final String? name;
  final int? revokedAtMs;
}

/// The parsed/authored form of the canonical list.
class DeviceList {
  const DeviceList({
    required this.userId,
    required this.version,
    required this.devices,
  });

  final int userId;
  final int version;
  final List<DeviceListEntry> devices;
}

/// Thrown by [parseCanonicalDeviceList] with a stable machine-readable
/// [reason]; every malformed input is a rejection, never a best-effort parse.
class CanonicalDeviceListException extends FormatException {
  CanonicalDeviceListException(this.reason)
    : super('canonical device list rejected: $reason');

  final String reason;
}

bool _validString(String value, int maxLength) {
  if (value.isEmpty || value.length > maxLength) return false;
  for (final unit in value.codeUnits) {
    // Control characters rejected (spec §3), including DEL.
    if (unit < 0x20 || unit == 0x7f) return false;
  }
  return true;
}

/// Canonical JSON string escaping: exactly `"` and `\` are escaped, control
/// characters are rejected upstream, everything else is raw UTF-8. Mirrored
/// byte-for-byte by the server's writer — do not swap in jsonEncode, whose
/// escaping rules differ across languages.
String _escape(String value) =>
    value.replaceAll('\\', r'\\').replaceAll('"', r'\"');

void _writeEntry(StringBuffer out, DeviceListEntry d) {
  // Device object keys in sorted order: addedAt, deviceId, name?, platform,
  // revokedAt? (spec §3: sorted keys; the top level alone puts userId and
  // version first).
  out.write('{"addedAt":${d.addedAtMs},"deviceId":${d.deviceId}');
  final name = d.name;
  if (name != null) out.write(',"name":"${_escape(name)}"');
  out.write(',"platform":"${_escape(d.platform)}"');
  final revokedAt = d.revokedAtMs;
  if (revokedAt != null) out.write(',"revokedAt":$revokedAt');
  out.write('}');
}

/// Serializes [list] to its canonical bytes, enforcing every §3 constraint at
/// SIGN time (the parse-time re-validation is [parseCanonicalDeviceList]).
Uint8List encodeCanonicalDeviceList(DeviceList list) {
  if (list.userId < 1) throw ArgumentError('userId must be a positive int');
  if (list.version < 1) throw ArgumentError('version must be >= 1');
  if (list.devices.isEmpty || list.devices.length > kDeviceListMaxEntries) {
    throw ArgumentError('devices must hold 1..$kDeviceListMaxEntries entries');
  }
  var previousDeviceId = 0;
  for (final d in list.devices) {
    // Ascending unique deviceIds: the ONE ordering a verifier can check, so
    // two encodings of the same set cannot both be canonical (ambiguity is
    // rejected, falsification 23).
    if (d.deviceId <= previousDeviceId) {
      throw ArgumentError('devices must be sorted by strictly ascending id');
    }
    previousDeviceId = d.deviceId;
    if (d.addedAtMs < 0 || (d.revokedAtMs != null && d.revokedAtMs! < 0)) {
      throw ArgumentError('timestamps must be non-negative integers');
    }
    if (!_validString(d.platform, kDevicePlatformMaxLength)) {
      throw ArgumentError(
        'platform must be 1..$kDevicePlatformMaxLength '
        'chars without control characters',
      );
    }
    if (d.name != null && !_validString(d.name!, kDeviceNameMaxLength)) {
      throw ArgumentError(
        'name must be 1..$kDeviceNameMaxLength '
        'chars without control characters',
      );
    }
  }

  final out = StringBuffer()
    ..write('{"userId":${list.userId},"version":${list.version},"devices":[');
  for (var i = 0; i < list.devices.length; i++) {
    if (i > 0) out.write(',');
    _writeEntry(out, list.devices[i]);
  }
  out.write(']}');
  return Uint8List.fromList(utf8.encode(out.toString()));
}

int _requireInt(dynamic value, String field) {
  if (value is! int) throw CanonicalDeviceListException('$field not an int');
  return value;
}

String _requireString(dynamic value, String field) {
  if (value is! String) {
    throw CanonicalDeviceListException('$field not a string');
  }
  return value;
}

/// Strictly parses canonical device-list [bytes].
///
/// Never verify a signature over anything but the received bytes — this
/// parser exists to VALIDATE those bytes after (or independently of) the
/// signature check, and it re-encodes only to prove the input is the one
/// canonical form (falsification 23).
DeviceList parseCanonicalDeviceList(Uint8List bytes) {
  final String text;
  try {
    text = utf8.decode(bytes); // strict: malformed UTF-8 throws
  } on FormatException {
    throw CanonicalDeviceListException('not valid UTF-8');
  }
  final dynamic decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw CanonicalDeviceListException('not valid JSON');
  }
  if (decoded is! Map<String, dynamic>) {
    throw CanonicalDeviceListException('top level not an object');
  }
  if (decoded.length != 3 ||
      !decoded.containsKey('userId') ||
      !decoded.containsKey('version') ||
      !decoded.containsKey('devices')) {
    throw CanonicalDeviceListException(
      'top-level keys must be exactly '
      'userId, version, devices',
    );
  }
  final userId = _requireInt(decoded['userId'], 'userId');
  final version = _requireInt(decoded['version'], 'version');
  final rawDevices = decoded['devices'];
  if (rawDevices is! List) {
    throw CanonicalDeviceListException('devices not an array');
  }

  final devices = <DeviceListEntry>[];
  for (final rawEntry in rawDevices) {
    if (rawEntry is! Map<String, dynamic>) {
      throw CanonicalDeviceListException('device entry not an object');
    }
    final allowed = {'addedAt', 'deviceId', 'name', 'platform', 'revokedAt'};
    if (rawEntry.keys.any((k) => !allowed.contains(k)) ||
        !rawEntry.containsKey('addedAt') ||
        !rawEntry.containsKey('deviceId') ||
        !rawEntry.containsKey('platform')) {
      throw CanonicalDeviceListException('device entry keys invalid');
    }
    devices.add(
      DeviceListEntry(
        deviceId: _requireInt(rawEntry['deviceId'], 'deviceId'),
        platform: _requireString(rawEntry['platform'], 'platform'),
        addedAtMs: _requireInt(rawEntry['addedAt'], 'addedAt'),
        name: rawEntry.containsKey('name')
            ? _requireString(rawEntry['name'], 'name')
            : null,
        revokedAtMs: rawEntry.containsKey('revokedAt')
            ? _requireInt(rawEntry['revokedAt'], 'revokedAt')
            : null,
      ),
    );
  }

  final list = DeviceList(userId: userId, version: version, devices: devices);
  final Uint8List reEncoded;
  try {
    // Re-encode runs the writer's own constraint checks (ranges, ordering,
    // control characters), so a structurally-typed but out-of-range input is
    // rejected here too.
    reEncoded = encodeCanonicalDeviceList(list);
  } on ArgumentError catch (e) {
    throw CanonicalDeviceListException(e.message as String);
  }
  if (reEncoded.length != bytes.length) {
    throw CanonicalDeviceListException('not canonical bytes');
  }
  for (var i = 0; i < bytes.length; i++) {
    if (reEncoded[i] != bytes[i]) {
      throw CanonicalDeviceListException('not canonical bytes');
    }
  }
  return list;
}
