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
}
