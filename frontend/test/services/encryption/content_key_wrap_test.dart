import 'dart:convert';
import 'dart:typed_data';

import 'package:fireplace/services/encryption/content_key_manager.dart';
import 'package:fireplace/services/encryption/content_key_wrap.dart';
import 'package:fireplace/services/encryption/content_sealer.dart';
import 'package:fireplace/services/secure_kv.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reversible stand-in for AES-GCM: the wrap logic under test is about
/// key HANDLING, not the cipher (the real primitive has its own tests and the
/// on-device run). Keyed so a wrong KEK genuinely fails to open, which is the
/// case that must never read as "key absent".
class _FakeSealer implements ContentSealer {
  @override
  Future<Uint8List?> seal(Uint8List key, Uint8List plaintext) async =>
      Uint8List.fromList([...key.take(4), ...plaintext]);

  @override
  Future<Uint8List?> unseal(Uint8List key, Uint8List sealed) async {
    if (sealed.length < 4) return null;
    for (var i = 0; i < 4; i++) {
      if (sealed[i] != key[i]) return null; // wrong KEK
    }
    return Uint8List.fromList(sealed.sublist(4));
  }
}

/// Seals but never opens: the shape of a cipher that "succeeds" while
/// producing bytes nothing can read back. The arm step exists for this.
class _OneWaySealer implements ContentSealer {
  @override
  Future<Uint8List?> seal(Uint8List key, Uint8List plaintext) async =>
      Uint8List.fromList([9, 9, 9, 9, ...plaintext]);

  @override
  Future<Uint8List?> unseal(Uint8List key, Uint8List sealed) async => null;
}

class _FakeSecureKv implements SecureKv {
  final Map<String, String> store = {};
  bool throwOnReadAll = false;

  @override
  Future<String?> read(String key) async => store[key];

  @override
  Future<void> write(String key, String value) async => store[key] = value;

  @override
  Future<void> delete(String key) async => store.remove(key);

  @override
  Future<Map<String, String>> readAll() async {
    if (throwOnReadAll) throw Exception('enumeration failed');
    return Map.of(store);
  }
}

Uint8List _kek(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (seed + i) & 0xff));

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  late _FakeSecureKv secure;
  late ContentKeyWrap wrap;

  setUp(() {
    secure = _FakeSecureKv();
    wrap = ContentKeyWrap(sealer: _FakeSealer(), meta: secure);
  });

  group('WrappedContentKey envelope', () {
    test('is recognizable without the key — that is the whole point', () async {
      wrap.unlock(kek: _kek(1), kekId: 'kek1');
      final envelope = await wrap.wrapKey(_kek(9));

      expect(envelope, isNotNull);
      // The prefix and kekId stay CLEARTEXT for the same reason `fpsig1:`
      // does: every loss-vs-locked decision upstream is made by looking at
      // the stored string without being able to open it.
      expect(WrappedContentKey.isEnvelope(envelope!), isTrue);
      expect(envelope.startsWith('fpwk1:kek1:'), isTrue);
      expect(WrappedContentKey.kekIdOf(envelope), 'kek1');
    });

    test('a raw hex key is not mistaken for an envelope', () {
      expect(WrappedContentKey.isEnvelope(_hex(_kek(3))), isFalse);
      expect(WrappedContentKey.isEnvelope(''), isFalse);
    });

    test('round-trips only under the KEK that wrapped it', () async {
      wrap.unlock(kek: _kek(1), kekId: 'kek1');
      final envelope = (await wrap.wrapKey(_kek(9)))!;

      expect(await wrap.unwrapKey(envelope), _kek(9));

      final other = ContentKeyWrap(sealer: _FakeSealer())
        ..unlock(kek: _kek(2), kekId: 'kek1');
      expect(await other.unwrapKey(envelope), isNull);
    });

    test('a locked vault can neither wrap nor unwrap', () async {
      wrap.unlock(kek: _kek(1), kekId: 'kek1');
      final envelope = (await wrap.wrapKey(_kek(9)))!;
      wrap.lock();

      expect(wrap.isLocked, isTrue);
      expect(await wrap.wrapKey(_kek(9)), isNull);
      expect(await wrap.unwrapKey(envelope), isNull);
    });
  });

  group('ContentKeyManager inventory with wrapping', () {
    test('serves unwrapped keys while the vault is open', () async {
      wrap.unlock(kek: _kek(1), kekId: 'kek1');
      final manager = ContentKeyManager(secure, wrap: wrap);
      secure.store['fp_content_key_kidA'] = (await wrap.wrapKey(_kek(9)))!;

      final inv = await manager.inventory();

      expect(inv, isNotNull);
      expect(inv!.keys['kidA'], _kek(9));
      expect(inv.lockedKeyCount, 0);
    });

    // THE test. A wrapped key that cannot be opened is PRESENT-BUT-LOCKED.
    // If it were merely dropped (the pre-Phase-2 behaviour for any value that
    // is not 32 raw bytes), the store above would see zero keys, and with
    // zero sealed rows it would mint a fresh key and seal over the real one —
    // or fall back to plaintext. That is the 0.1.10 identity-loss shape.
    test('a wrapped key with the vault LOCKED counts as locked, not absent',
        () async {
      wrap.unlock(kek: _kek(1), kekId: 'kek1');
      secure.store['fp_content_key_kidA'] = (await wrap.wrapKey(_kek(9)))!;
      wrap.lock();
      final manager = ContentKeyManager(secure, wrap: wrap);

      final inv = await manager.inventory();

      expect(inv, isNotNull, reason: 'enumeration SUCCEEDED — not null');
      expect(inv!.keys, isEmpty);
      expect(inv.lockedKeyCount, 1);
    });

    test('a wrapped key the vault cannot open counts as locked too', () async {
      final writer = ContentKeyWrap(sealer: _FakeSealer())
        ..unlock(kek: _kek(1), kekId: 'kek1');
      secure.store['fp_content_key_kidA'] = (await writer.wrapKey(_kek(9)))!;
      // Same kekId, different KEK: what a wrong passcode looks like.
      wrap.unlock(kek: _kek(2), kekId: 'kek1');
      final manager = ContentKeyManager(secure, wrap: wrap);

      final inv = await manager.inventory();

      expect(inv!.keys, isEmpty);
      expect(inv.lockedKeyCount, 1);
    });

    test('plain hex keys still work when no wrapping is configured', () async {
      secure.store['fp_content_key_kidA'] = _hex(_kek(9));
      final manager = ContentKeyManager(secure);

      final inv = await manager.inventory();

      expect(inv!.keys['kidA'], _kek(9));
      expect(inv.lockedKeyCount, 0);
    });

    test('an enumeration failure is still null, never locked', () async {
      secure.throwOnReadAll = true;
      final manager = ContentKeyManager(secure, wrap: wrap);

      expect(await manager.inventory(), isNull);
    });
  });

  group('minting under wrapping', () {
    Future<void> turnWrappingOn() => wrap
        .enableWrapping(
          kek: _kek(1),
          kekId: 'kek1',
          iterations: 600000,
          saltB64: 'AAAA',
        )
        .then((ok) => expect(ok, isTrue));

    test('mints WRAPPED keys while unlocked, and they read back', () async {
      await turnWrappingOn();
      final manager = ContentKeyManager(secure, wrap: wrap);

      final kid = await manager.mintContentKey();

      expect(kid, isNotNull);
      final stored = secure.store['fp_content_key_$kid']!;
      expect(WrappedContentKey.isEnvelope(stored), isTrue,
          reason: 'a key minted under wrapping must never land as raw hex');
      final inv = await manager.inventory();
      expect(inv!.keys[kid], isNotNull);
    });

    test('refuses to mint while locked instead of minting a bypass', () async {
      await turnWrappingOn();
      wrap.lock();
      final manager = ContentKeyManager(secure, wrap: wrap);

      expect(await manager.mintContentKey(), isNull);
      expect(
        secure.store.keys.where((k) => k.startsWith('fp_content_key_')),
        isEmpty,
        reason: 'a key minted while locked would be readable without the '
            'passcode — exactly the door Phase 2 closes',
      );
    });
  });


  // Wrapping OFF is not the same as wrapping ON but locked, and conflating
  // them would brick every web user who never sets a passcode: the vault is
  // "locked" for them forever, so a mint refusal would take the store into
  // its plaintext fallback on a normal fresh install.
  group('wrapping enabled vs merely locked', () {
    test('a vault with no meta record reports wrapping OFF', () async {
      final off = ContentKeyWrap(sealer: _FakeSealer(), meta: secure);

      expect(await off.isWrappingOn(), isFalse);
      expect(off.isLocked, isTrue);
    });

    test('mints RAW keys while wrapping is off, even though it is locked',
        () async {
      final manager = ContentKeyManager(
        secure,
        wrap: ContentKeyWrap(sealer: _FakeSealer(), meta: secure),
      );

      final kid = await manager.mintContentKey();

      expect(kid, isNotNull);
      expect(
        WrappedContentKey.isEnvelope(secure.store['fp_content_key_$kid']!),
        isFalse,
      );
    });

    test('enable writes the meta record, disable removes it', () async {
      final vault = ContentKeyWrap(sealer: _FakeSealer(), meta: secure);

      await vault.enableWrapping(
        kek: _kek(1),
        kekId: 'kek1',
        iterations: 600000,
        saltB64: 'AAAA',
      );
      expect(await vault.isWrappingOn(), isTrue);
      expect(vault.isLocked, isFalse, reason: 'enabling also unlocks');
      expect(secure.store[PasscodeKekMeta.storageKey], isNotNull);

      await vault.disableWrapping();
      expect(await vault.isWrappingOn(), isFalse);
      expect(vault.isLocked, isTrue);
      expect(secure.store.containsKey(PasscodeKekMeta.storageKey), isFalse);
    });
    test('refuses to mint once wrapping is on and the vault is locked',
        () async {
      final vault = ContentKeyWrap(sealer: _FakeSealer(), meta: secure);
      await vault.enableWrapping(
        kek: _kek(1),
        kekId: 'kek1',
        iterations: 600000,
        saltB64: 'AAAA',
      );
      vault.lock();
      final manager = ContentKeyManager(secure, wrap: vault);

      expect(await manager.mintContentKey(), isNull);
    });
  });


  group('migration', () {
    const prefixes = ['fp_content_key_', 'fp_sig_key_'];

    Future<void> turnOn(ContentKeyWrap v, {int seed = 1, String id = 'kek1'}) =>
        v.enableWrapping(
          kek: _kek(seed),
          kekId: id,
          iterations: 600000,
          saltB64: 'AAAA',
        ).then((ok) => expect(ok, isTrue));

    test('wraps existing raw keys in place, and is idempotent', () async {
      secure.store['fp_content_key_kidA'] = _hex(_kek(9));
      secure.store['fp_sig_key_kidB'] = _hex(_kek(10));
      secure.store['unrelated'] = 'leave-me';
      await turnOn(wrap);

      expect(await wrap.wrapRawKeys(prefixes), 2);
      expect(
        WrappedContentKey.isEnvelope(secure.store['fp_content_key_kidA']!),
        isTrue,
      );
      expect(secure.store['unrelated'], 'leave-me');
      // A second pass has nothing left to do — this is what makes an
      // interrupted migration safe to resume on every unlock.
      expect(await wrap.wrapRawKeys(prefixes), 0);

      final inv = await ContentKeyManager(secure, wrap: wrap).inventory();
      expect(inv!.keys['kidA'], _kek(9));
      expect(inv.lockedKeyCount, 0);
    });

    test('a key that cannot be proven readable is rolled back to raw',
        () async {
      // Sealer that seals but refuses to open: the arm step must catch it.
      final oneWay = ContentKeyWrap(
        sealer: _OneWaySealer(),
        meta: secure,
      );
      secure.store['fp_content_key_kidA'] = _hex(_kek(9));
      await turnOn(oneWay);

      expect(await oneWay.wrapRawKeys(prefixes), 0);
      expect(secure.store['fp_content_key_kidA'], _hex(_kek(9)),
          reason: 'an envelope the vault cannot open would brick the store');
    });

    test('unwraps everything back to raw before wrapping is turned off',
        () async {
      secure.store['fp_content_key_kidA'] = _hex(_kek(9));
      await turnOn(wrap);
      await wrap.wrapRawKeys(prefixes);

      expect(await wrap.unwrapAllKeys(prefixes), isTrue);
      expect(secure.store['fp_content_key_kidA'], _hex(_kek(9)));

      await wrap.disableWrapping();
      final inv = await ContentKeyManager(secure, wrap: wrap).inventory();
      expect(inv!.keys['kidA'], _kek(9),
          reason: 'a disabled device must read its keys with no passcode');
    });

    test('rekey moves every key to a new KEK (a passcode change)', () async {
      secure.store['fp_content_key_kidA'] = _hex(_kek(9));
      await turnOn(wrap);
      await wrap.wrapRawKeys(prefixes);

      final ok = await wrap.rekey(
        newKek: _kek(42),
        newKekId: 'kek2',
        iterations: 600000,
        saltB64: 'BBBB',
        prefixes: prefixes,
      );

      expect(ok, isTrue);
      expect(WrappedContentKey.kekIdOf(secure.store['fp_content_key_kidA']!),
          'kek2');
      // The OLD KEK must no longer open it.
      final old = ContentKeyWrap(sealer: _FakeSealer(), meta: secure)
        ..unlock(kek: _kek(1), kekId: 'kek1');
      expect(
        await old.unwrapKey(secure.store['fp_content_key_kidA']!),
        isNull,
      );
      // The new one does.
      final inv = await ContentKeyManager(secure, wrap: wrap).inventory();
      expect(inv!.keys['kidA'], _kek(9));
    });

    test('migration refuses to run while locked', () async {
      secure.store['fp_content_key_kidA'] = _hex(_kek(9));
      await turnOn(wrap);
      wrap.lock();

      expect(await wrap.wrapRawKeys(prefixes), isNull);
      expect(await wrap.unwrapAllKeys(prefixes), isFalse);
    });
  });
  group('PasscodeKekMeta', () {
    test('carries its own cost factor so it can be raised later', () {
      const meta = PasscodeKekMeta(
        kekId: 'kek1',
        iterations: 600000,
        saltB64: 'AAAA',
      );

      final decoded = PasscodeKekMeta.decode(jsonEncode(meta.toJson()));

      expect(decoded, isNotNull);
      expect(decoded!.kekId, 'kek1');
      expect(decoded.iterations, 600000);
      expect(decoded.saltB64, 'AAAA');
    });

    test('garbage decodes to null rather than a default', () {
      expect(PasscodeKekMeta.decode('not json'), isNull);
      expect(PasscodeKekMeta.decode('{"kekId":"k"}'), isNull);
    });
  });
}
