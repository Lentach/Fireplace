import {
  CanonicalDeviceListError,
  encodeCanonicalDeviceList,
  parseCanonicalDeviceList,
  ParsedDeviceList,
} from './device-list-canonical.util';

/**
 * Falsification 23 (spec §3/§10): `listCanonical` has exactly ONE byte form;
 * duplicate keys and every other re-encoding of the same list — whitespace,
 * key reordering, number/escape variants — are rejected AT PARSE. The Dart
 * mirror (device_list_canonical.dart) is pinned by the frontend suite; the
 * wire harness proves both ends agree on real bytes.
 */

const LIST: ParsedDeviceList = {
  userId: 42,
  version: 1,
  devices: [{ deviceId: 1, platform: 'android', addedAt: 1755000000000 }],
};

const CANONICAL =
  '{"userId":42,"version":1,"devices":[' +
  '{"addedAt":1755000000000,"deviceId":1,"platform":"android"}]}';

const parse = (text: string) =>
  parseCanonicalDeviceList(Buffer.from(text, 'utf8'));

describe('encodeCanonicalDeviceList', () => {
  it('produces the one canonical byte form', () => {
    expect(encodeCanonicalDeviceList(LIST).toString('utf8')).toBe(CANONICAL);
  });

  it('serializes optional name/revokedAt in sorted key order with minimal escaping', () => {
    const encoded = encodeCanonicalDeviceList({
      userId: 42,
      version: 2,
      devices: [
        { deviceId: 1, platform: 'android', addedAt: 5 },
        {
          deviceId: 3,
          platform: 'web',
          addedAt: 6,
          name: 'a "quoted\\" name',
          revokedAt: 7,
        },
      ],
    });
    expect(encoded.toString('utf8')).toBe(
      '{"userId":42,"version":2,"devices":[' +
        '{"addedAt":5,"deviceId":1,"platform":"android"},' +
        '{"addedAt":6,"deviceId":3,"name":"a \\"quoted\\\\\\" name",' +
        '"platform":"web","revokedAt":7}]}',
    );
    // And the escaped form round-trips through the strict parser.
    expect(parseCanonicalDeviceList(encoded).devices[1].name).toBe(
      'a "quoted\\" name',
    );
  });

  it.each<[string, ParsedDeviceList]>([
    [
      'unsorted deviceIds',
      {
        userId: 42,
        version: 1,
        devices: [
          { deviceId: 2, platform: 'a', addedAt: 1 },
          { deviceId: 1, platform: 'a', addedAt: 1 },
        ],
      },
    ],
    [
      'duplicate deviceIds',
      {
        userId: 42,
        version: 1,
        devices: [
          { deviceId: 1, platform: 'a', addedAt: 1 },
          { deviceId: 1, platform: 'a', addedAt: 1 },
        ],
      },
    ],
    [
      'control character in platform',
      {
        userId: 42,
        version: 1,
        devices: [{ deviceId: 1, platform: 'a\nb', addedAt: 1 }],
      },
    ],
    [
      'oversized name',
      {
        userId: 42,
        version: 1,
        devices: [
          { deviceId: 1, platform: 'a', addedAt: 1, name: 'x'.repeat(65) },
        ],
      },
    ],
    [
      'non-NFC name',
      {
        userId: 42,
        version: 1,
        // U+0065 U+0301 (e + combining acute) is NFD; NFC is U+00E9.
        devices: [{ deviceId: 1, platform: 'a', addedAt: 1, name: 'e\u0301' }],
      },
    ],
    ['empty device set', { userId: 42, version: 1, devices: [] }],
    ['zero version', { ...LIST, version: 0 }],
    ['fractional version', { ...LIST, version: 1.5 }],
    [
      'negative timestamp',
      {
        userId: 42,
        version: 1,
        devices: [{ deviceId: 1, platform: 'a', addedAt: -1 }],
      },
    ],
  ])('rejects %s at write time', (_label, list) => {
    expect(() => encodeCanonicalDeviceList(list)).toThrow(
      CanonicalDeviceListError,
    );
  });
});

describe('parseCanonicalDeviceList (falsification 23)', () => {
  it('round-trips the canonical bytes', () => {
    const parsed = parse(CANONICAL);
    expect(parsed).toEqual(LIST);
  });

  it.each([
    [
      'duplicate keys',
      CANONICAL.replace('"version":1', '"version":1,"version":1'),
    ],
    ['whitespace', CANONICAL.replace('"userId":42', '"userId": 42')],
    [
      'reordered top-level keys',
      '{"version":1,"userId":42,"devices":[' +
        '{"addedAt":1755000000000,"deviceId":1,"platform":"android"}]}',
    ],
    [
      'reordered device keys',
      '{"userId":42,"version":1,"devices":[' +
        '{"deviceId":1,"addedAt":1755000000000,"platform":"android"}]}',
    ],
    ['float version', CANONICAL.replace('"version":1', '"version":1.0')],
    [
      'exponent timestamp',
      CANONICAL.replace('"addedAt":1755000000000', '"addedAt":1.755e12'),
    ],
    ['unicode escape', CANONICAL.replace('android', 'a\\u006edroid')],
    ['missing devices key', '{"userId":42,"version":1}'],
    [
      'unknown device key',
      CANONICAL.replace(
        '"platform":"android"',
        '"platform":"android","extra":1',
      ),
    ],
    [
      'out-of-order devices',
      '{"userId":42,"version":1,"devices":[' +
        '{"addedAt":1,"deviceId":2,"platform":"a"},' +
        '{"addedAt":1,"deviceId":1,"platform":"a"}]}',
    ],
    ['not JSON', 'not json'],
    ['top-level array', '[]'],
    ['string version', CANONICAL.replace('"version":1', '"version":"1"')],
  ])('rejects %s at parse', (_label, text) => {
    expect(() => parse(text)).toThrow(CanonicalDeviceListError);
  });

  it('rejects malformed UTF-8 bytes', () => {
    expect(() =>
      parseCanonicalDeviceList(Buffer.from([0xff, 0xfe, 0x7b])),
    ).toThrow(CanonicalDeviceListError);
  });

  it('agrees byte-for-byte with the pinned Dart client canonical', () => {
    // The exact base64 the vector generator's Dart writer produced for
    // { userId: 4242, version: 1, devices: [device 1] } — both languages
    // must emit identical bytes or signatures stop verifying cross-language.
    const dartCanonical = Buffer.from(
      'eyJ1c2VySWQiOjQyNDIsInZlcnNpb24iOjEsImRldmljZXMiOlt7ImFkZGVkQXQiOjE3NTU2MDAwMDAwMDAsImRldmljZUlkIjoxLCJwbGF0Zm9ybSI6ImFuZHJvaWQifV19',
      'base64',
    );
    const parsed = parseCanonicalDeviceList(dartCanonical);
    expect(encodeCanonicalDeviceList(parsed).equals(dartCanonical)).toBe(true);
    expect(parsed).toEqual({
      userId: 4242,
      version: 1,
      devices: [{ deviceId: 1, platform: 'android', addedAt: 1755600000000 }],
    });
  });
});
