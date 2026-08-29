// DAK persistence laws (Phase 2 T3 rider): the record is ONE atomic JSON
// blob, a write only counts after a verified fresh read-back (armed-write
// discipline — the enroll emit is gated on it), damage is never absence, and
// clear leaves storage empty (falsification 18's abort hygiene needs a real
// delete, not an overwrite).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/device_link/dak_store.dart';
import 'package:fireplace/services/encryption/signal_stores.dart';

/// DualStorage whose reads can be scripted to lie — the armed write must
/// catch a store that acknowledges without persisting.
class _LyingDualStorage extends DualStorage {
  _LyingDualStorage() : super(const FlutterSecureStorage());

  bool swallowWrites = false;

  @override
  Future<void> write({required String key, required String value}) async {
    if (swallowWrites) return; // acknowledged, never persisted
    return super.write(key: key, value: value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const record = DakRecord(
    userId: 7,
    dakPub: 'ZGFrUHVi',
    dakPriv: 'ZGFrUHJpdg==',
    createdAtMs: 1755600000000,
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('persistArmed writes one record and read returns it field-exact', () async {
    final store = DakStore(storage: DualStorage(const FlutterSecureStorage()));

    await store.persistArmed(record);

    final loaded = await store.read(userId: 7);
    expect(loaded, isNotNull);
    expect(loaded!.toJson(), record.toJson());
    // Another account's slot stays empty — the record is per-user.
    expect(await store.read(userId: 8), isNull);
  });

  test('a store that acknowledges without persisting fails the arm', () async {
    final lying = _LyingDualStorage()..swallowWrites = true;
    final store = DakStore(storage: lying);

    await expectLater(store.persistArmed(record), throwsStateError);
  });

  test('an unreadable record is damage, never absence', () async {
    final storage = DualStorage(const FlutterSecureStorage());
    await storage.write(key: 'dak_record_v1_7', value: 'not json');
    final store = DakStore(storage: storage);

    // Treating this as absent would invite minting a SECOND DAK the
    // server's first-write-wins enrollment refuses forever.
    await expectLater(store.read(userId: 7), throwsStateError);
  });

  test('a record missing a field is damage too', () async {
    final storage = DualStorage(const FlutterSecureStorage());
    await storage.write(
      key: 'dak_record_v1_7',
      value: '{"userId":7,"dakPub":"x"}',
    );
    final store = DakStore(storage: storage);

    await expectLater(store.read(userId: 7), throwsStateError);
  });

  test('clear leaves storage empty (abort hygiene, falsification 18)', () async {
    final storage = DualStorage(const FlutterSecureStorage());
    final store = DakStore(storage: storage);
    await store.persistArmed(record);

    await store.clear(userId: 7);

    expect(await store.read(userId: 7), isNull);
    expect(await storage.read(key: 'dak_record_v1_7'), isNull);
  });

  // Amendment (liii): a replacement-enrollment offer cannot be authenticated by
  // this device, so testing one must not spend the authority it already holds.
  group('pending slot ((liii))', () {
    const candidate = DakRecord(
      userId: 7,
      dakPub: 'Y2FuZFB1Yg==',
      dakPriv: 'Y2FuZFByaXY=',
      createdAtMs: 1755600001000,
    );

    test('a pending write leaves the LIVE record untouched', () async {
      final store = DakStore(storage: DualStorage(const FlutterSecureStorage()));
      await store.persistArmed(record);

      await store.persistPendingArmed(candidate);

      // This is the whole finding: the old code overwrote the live record here,
      // so a server that then answered `already_enrolled` had destroyed the
      // account's only DAK private half.
      expect((await store.read(userId: 7))!.dakPub, record.dakPub);
      expect((await store.readPending(userId: 7))!.dakPub, candidate.dakPub);
    });

    test('a refusal clears the candidate and the live authority survives', () async {
      final store = DakStore(storage: DualStorage(const FlutterSecureStorage()));
      await store.persistArmed(record);
      await store.persistPendingArmed(candidate);

      await store.clearPending(userId: 7);

      expect((await store.read(userId: 7))!.dakPub, record.dakPub);
      expect(await store.readPending(userId: 7), isNull);
    });

    test('promotion makes the candidate live and drops the pending slot', () async {
      final storage = DualStorage(const FlutterSecureStorage());
      final store = DakStore(storage: storage);
      await store.persistArmed(record);
      await store.persistPendingArmed(candidate);

      await store.promotePending(userId: 7);

      expect((await store.read(userId: 7))!.dakPub, candidate.dakPub);
      expect(await store.readPending(userId: 7), isNull);
      expect(await storage.read(key: 'dak_pending_v1_7'), isNull);
    });

    test('promoting nothing throws rather than clearing the live record', () async {
      final store = DakStore(storage: DualStorage(const FlutterSecureStorage()));
      await store.persistArmed(record);

      await expectLater(
        store.promotePending(userId: 7),
        throwsA(isA<StateError>()),
      );
      expect((await store.read(userId: 7))!.dakPub, record.dakPub);
    });

    test('the pending write is ARMED: a lying store is caught', () async {
      final storage = _LyingDualStorage();
      final store = DakStore(storage: storage);
      storage.swallowWrites = true;

      await expectLater(
        store.persistPendingArmed(candidate),
        throwsA(isA<StateError>()),
        reason: 'the enroll emit is gated on this write being proven',
      );
    });
  });
}
