// Canonical device-list bytes (multi-device spec §3, Phase 2 T2).
//
// Falsification 23 lives here on the client side: `listCanonical` has exactly
// ONE byte form, and every re-encoding of the same list — duplicate keys,
// whitespace, key reordering, escape/number variants — is rejected AT PARSE.

import 'dart:convert';
import 'dart:typed_data';

import 'package:fireplace/services/device_list/device_list_canonical.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  final list = DeviceList(
    userId: 42,
    version: 1,
    devices: const [
      DeviceListEntry(
        deviceId: 1,
        platform: 'android',
        addedAtMs: 1755000000000,
      ),
    ],
  );

  group('encodeCanonicalDeviceList', () {
    test('produces the one canonical byte form', () {
      expect(
        utf8.decode(encodeCanonicalDeviceList(list)),
        '{"userId":42,"version":1,"devices":['
        '{"addedAt":1755000000000,"deviceId":1,"platform":"android"}]}',
      );
    });

    test('optional name and revokedAt serialize in sorted key order', () {
      final encoded = encodeCanonicalDeviceList(
        DeviceList(
          userId: 42,
          version: 2,
          devices: const [
            DeviceListEntry(deviceId: 1, platform: 'android', addedAtMs: 5),
            DeviceListEntry(
              deviceId: 3,
              platform: 'web',
              addedAtMs: 6,
              name: 'a "quoted\\" name',
              revokedAtMs: 7,
            ),
          ],
        ),
      );
      expect(
        utf8.decode(encoded),
        '{"userId":42,"version":2,"devices":['
        '{"addedAt":5,"deviceId":1,"platform":"android"},'
        '{"addedAt":6,"deviceId":3,"name":"a \\"quoted\\\\\\" name",'
        '"platform":"web","revokedAt":7}]}',
      );
      // The escaped form must round-trip through the strict parser.
      final parsed = parseCanonicalDeviceList(encoded);
      expect(parsed.devices[1].name, 'a "quoted\\" name');
    });

    test('rejects unsorted or duplicate deviceIds (ambiguity)', () {
      expect(
        () => encodeCanonicalDeviceList(
          DeviceList(
            userId: 42,
            version: 1,
            devices: const [
              DeviceListEntry(deviceId: 2, platform: 'a', addedAtMs: 1),
              DeviceListEntry(deviceId: 1, platform: 'a', addedAtMs: 1),
            ],
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => encodeCanonicalDeviceList(
          DeviceList(
            userId: 42,
            version: 1,
            devices: const [
              DeviceListEntry(deviceId: 1, platform: 'a', addedAtMs: 1),
              DeviceListEntry(deviceId: 1, platform: 'a', addedAtMs: 1),
            ],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('rejects control characters and empty/oversized strings', () {
      expect(
        () => encodeCanonicalDeviceList(
          DeviceList(
            userId: 42,
            version: 1,
            devices: const [
              DeviceListEntry(deviceId: 1, platform: 'a\nb', addedAtMs: 1),
            ],
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => encodeCanonicalDeviceList(
          DeviceList(
            userId: 42,
            version: 1,
            devices: [
              DeviceListEntry(
                deviceId: 1,
                platform: 'a',
                addedAtMs: 1,
                name: 'x' * 65,
              ),
            ],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('rejects an empty device set and non-positive version/userId', () {
      expect(
        () => encodeCanonicalDeviceList(
          const DeviceList(userId: 42, version: 1, devices: []),
        ),
        throwsArgumentError,
      );
      expect(
        () => encodeCanonicalDeviceList(
          DeviceList(userId: 42, version: 0, devices: list.devices),
        ),
        throwsArgumentError,
      );
    });
  });

  group('parseCanonicalDeviceList (falsification 23)', () {
    late String canonical;

    setUp(() {
      canonical = utf8.decode(encodeCanonicalDeviceList(list));
    });

    test('round-trips the canonical bytes', () {
      final parsed = parseCanonicalDeviceList(bytesOf(canonical));
      expect(parsed.userId, 42);
      expect(parsed.version, 1);
      expect(parsed.devices, hasLength(1));
      expect(parsed.devices.single.deviceId, 1);
      expect(parsed.devices.single.platform, 'android');
      expect(parsed.devices.single.addedAtMs, 1755000000000);
    });

    DeviceList parse(String text) => parseCanonicalDeviceList(bytesOf(text));

    test('rejects duplicate keys at parse', () {
      final dup = canonical.replaceFirst(
        '"version":1',
        '"version":1,"version":1',
      );
      expect(() => parse(dup), throwsA(isA<CanonicalDeviceListException>()));
    });

    test('rejects whitespace variants', () {
      expect(
        () => parse(canonical.replaceFirst('"userId":42', '"userId": 42')),
        throwsA(isA<CanonicalDeviceListException>()),
      );
    });

    test('rejects reordered top-level keys', () {
      expect(
        () => parse(
          '{"version":1,"userId":42,"devices":['
          '{"addedAt":1755000000000,"deviceId":1,"platform":"android"}]}',
        ),
        throwsA(isA<CanonicalDeviceListException>()),
      );
    });

    test('rejects reordered device keys', () {
      expect(
        () => parse(
          '{"userId":42,"version":1,"devices":['
          '{"deviceId":1,"addedAt":1755000000000,"platform":"android"}]}',
        ),
        throwsA(isA<CanonicalDeviceListException>()),
      );
    });

    test('rejects non-canonical number and escape forms', () {
      expect(
        () => parse(canonical.replaceFirst('"version":1', '"version":1.0')),
        throwsA(isA<CanonicalDeviceListException>()),
      );
      expect(
        () => parse(
          canonical.replaceFirst(
            '"addedAt":1755000000000',
            '"addedAt":1.755e12',
          ),
        ),
        throwsA(isA<CanonicalDeviceListException>()),
      );
      expect(
        () => parse(canonical.replaceFirst('android', r'a\u006edroid')),
        throwsA(isA<CanonicalDeviceListException>()),
      );
    });

    test('rejects missing and unknown keys', () {
      expect(
        () => parse('{"userId":42,"version":1}'),
        throwsA(isA<CanonicalDeviceListException>()),
      );
      expect(
        () => parse(
          canonical.replaceFirst(
            '"platform":"android"',
            '"platform":"android","extra":1',
          ),
        ),
        throwsA(isA<CanonicalDeviceListException>()),
      );
    });

    test('rejects out-of-order devices even when well-formed JSON', () {
      expect(
        () => parse(
          '{"userId":42,"version":1,"devices":['
          '{"addedAt":1,"deviceId":2,"platform":"a"},'
          '{"addedAt":1,"deviceId":1,"platform":"a"}]}',
        ),
        throwsA(isA<CanonicalDeviceListException>()),
      );
    });

    test('rejects malformed UTF-8 and non-JSON bytes', () {
      expect(
        () => parseCanonicalDeviceList(Uint8List.fromList([0xff, 0xfe, 0x7b])),
        throwsA(isA<CanonicalDeviceListException>()),
      );
      expect(
        () => parse('not json'),
        throwsA(isA<CanonicalDeviceListException>()),
      );
      expect(() => parse('[]'), throwsA(isA<CanonicalDeviceListException>()));
    });
  });
}
