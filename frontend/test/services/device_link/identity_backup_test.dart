import 'dart:convert';

import 'package:fireplace/services/device_link/identity_backup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/passcode_fakes.dart';

/// The (lxxviii) phrase-sealed identity backup codec.
///
/// The KDF and the cipher are injected fakes (the test binding has no
/// webcrypto native); what these tests pin is the codec's CONTRACT: the
/// round trip, the failure taxonomy (wrong phrase vs. damage), and the
/// pre-KDF parameter sanity that stops a hostile answer from buying an
/// unbounded derivation.
void main() {
  const payload = IdentityBackupPayload(
    userId: 9,
    identity: '{"pair":"AAEC","registrationId":123}',
    dak: '{"userId":9,"dakPub":"cHVi","dakPriv":"cHJ2","createdAtMs":1}',
  );
  const phrase = 'abandon ability able about above absent '
      'absorb abstract absurd abuse access accident';

  IdentityBackupCodec codec() =>
      IdentityBackupCodec(kdf: FakePasscodeKdf(), sealer: FakeContentSealer());

  test('seal → unseal round-trips the payload verbatim', () async {
    final sealed = await codec().seal(payload, phrase);
    expect(sealed.iterations, kIdentityBackupKdfIterations);
    expect(base64Decode(sealed.salt), hasLength(16));

    final opened = await codec().unseal(
      blob: sealed.blob,
      salt: sealed.salt,
      iterations: sealed.iterations,
      phrase: phrase,
    );
    expect(opened.userId, payload.userId);
    expect(opened.identity, payload.identity);
    expect(opened.dak, payload.dak);
  });

  test('a null dak survives the round trip as null', () async {
    const noDak = IdentityBackupPayload(
      userId: 9,
      identity: '{"pair":"AAEC","registrationId":123}',
      dak: null,
    );
    final sealed = await codec().seal(noDak, phrase);
    final opened = await codec().unseal(
      blob: sealed.blob,
      salt: sealed.salt,
      iterations: sealed.iterations,
      phrase: phrase,
    );
    expect(opened.dak, isNull);
  });

  test('phrase normalization: seal and unseal cannot drift', () async {
    final sealed = await codec().seal(payload, '  ${phrase.toUpperCase()}  ');
    final opened = await codec().unseal(
      blob: sealed.blob,
      salt: sealed.salt,
      iterations: sealed.iterations,
      phrase: phrase,
    );
    expect(opened.userId, payload.userId);
  });

  test('the wrong phrase throws IdentityBackupWrongPhrase, never Corrupt',
      () async {
    final sealed = await codec().seal(payload, phrase);
    await expectLater(
      codec().unseal(
        blob: sealed.blob,
        salt: sealed.salt,
        iterations: sealed.iterations,
        phrase: 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong',
      ),
      throwsA(isA<IdentityBackupWrongPhrase>()),
    );
  });

  test('damaged wire fields are Corrupt, never blamed on the phrase',
      () async {
    final sealed = await codec().seal(payload, phrase);
    // Bad base64.
    await expectLater(
      codec().unseal(
        blob: '!!!not-base64!!!',
        salt: sealed.salt,
        iterations: sealed.iterations,
        phrase: phrase,
      ),
      throwsA(isA<IdentityBackupCorrupt>()),
    );
    // Hostile iteration count: refused BEFORE any derivation.
    final kdf = FakePasscodeKdf();
    final counting = IdentityBackupCodec(kdf: kdf, sealer: FakeContentSealer());
    await expectLater(
      counting.unseal(
        blob: sealed.blob,
        salt: sealed.salt,
        iterations: 50000000,
        phrase: phrase,
      ),
      throwsA(isA<IdentityBackupCorrupt>()),
    );
    expect(kdf.calls, 0, reason: 'parameter sanity must run before the KDF');
    // Wrong salt length.
    await expectLater(
      codec().unseal(
        blob: sealed.blob,
        salt: base64Encode(List.filled(8, 1)),
        iterations: sealed.iterations,
        phrase: phrase,
      ),
      throwsA(isA<IdentityBackupCorrupt>()),
    );
  });

  test('an opened blob with a foreign shape is Corrupt', () async {
    // Seal raw non-payload JSON with the same fake pair, then open it.
    final sealer = FakeContentSealer();
    final kdf = FakePasscodeKdf();
    final c = IdentityBackupCodec(kdf: kdf, sealer: sealer);
    final sealed = await c.seal(payload, phrase);
    // Tamper: re-seal different JSON under the same derived key.
    final key = await kdf.derive(
      passcode: phrase,
      salt: base64Decode(sealed.salt),
      iterations: sealed.iterations,
    );
    final evil = await sealer.seal(
      key,
      utf8.encode('{"v":2,"userId":"x"}'),
    );
    await expectLater(
      c.unseal(
        blob: base64Encode(evil!),
        salt: sealed.salt,
        iterations: sealed.iterations,
        phrase: phrase,
      ),
      throwsA(isA<IdentityBackupCorrupt>()),
    );
  });

  test('wire form carries blob, salt, iterations and version 1', () async {
    final sealed = await codec().seal(payload, phrase);
    expect(sealed.toWire(), {
      'blob': sealed.blob,
      'salt': sealed.salt,
      'iterations': kIdentityBackupKdfIterations,
      'version': 1,
    });
  });
}
