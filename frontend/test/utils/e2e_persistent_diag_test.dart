import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/utils/e2e_diag_log.dart';
import 'package:fireplace/utils/e2e_persistent_diag.dart';

/// Tests for the durable failure-class diagnostic store [E2ePersistentDiag].
///
/// It mirrors events into the in-memory [E2eDiagLog] ring AND persists a
/// capped tail to SharedPreferences (key `e2e_diag_persist_v1`) so failure
/// events survive ring eviction and app restart.
///
/// Static-state caveat: `E2ePersistentDiag` holds static `_cache`/`_prefs`
/// and `E2eDiagLog` holds a static ring. Both are reset between tests by
/// clearing them and re-`init()`-ing against a fresh mock store in `setUp`.
/// The persistence write in `record` is fire-and-forget (`.ignore()`), so we
/// pump the event queue before reading the raw prefs list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const persistKey = 'e2e_diag_persist_v1';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await E2ePersistentDiag.clear();
    E2eDiagLog.clear();
    await E2ePersistentDiag.init();
  });

  tearDown(() async {
    await E2ePersistentDiag.clear();
    E2eDiagLog.clear();
  });

  test('record then entries contains a line with the step name and data',
      () {
    E2ePersistentDiag.record('Decryption failed', {'msgId': 42});

    expect(E2ePersistentDiag.entries, hasLength(1));
    final line = E2ePersistentDiag.entries.single;
    expect(line, contains('Decryption failed'));
    expect(line, contains('42'));
    // Date-stamped MM-DD HH:MM:SS prefix with the "step | {data}" tail.
    expect(
      line,
      matches(RegExp(r'^\d{2}-\d{2} \d{2}:\d{2}:\d{2} Decryption failed \| ')),
    );
  });

  test('record also mirrors into E2eDiagLog.entries', () {
    E2ePersistentDiag.record('Reset session', {'peer': 7});

    expect(E2eDiagLog.entries, hasLength(1));
    final mirrored = E2eDiagLog.entries.single;
    expect(mirrored, contains('Reset session'));
    expect(mirrored, contains('7'));
    // The persistent store also holds it.
    expect(E2ePersistentDiag.entries.single, contains('Reset session'));
  });

  test('cap keeps exactly 80 entries, newest retained and oldest dropped',
      () {
    for (var i = 0; i < 120; i++) {
      E2ePersistentDiag.record('evt', {'n': i});
    }

    expect(E2ePersistentDiag.entries, hasLength(80));
    // Oldest 40 (n 0..39) evicted; newest (n 119) retained.
    expect(E2ePersistentDiag.entries.first, contains('40'));
    expect(E2ePersistentDiag.entries.last, contains('119'));
    for (final line in E2ePersistentDiag.entries) {
      expect(line, contains('evt'));
    }
    // No trace of a dropped early entry remains.
    expect(
      E2ePersistentDiag.entries.any((l) => l.contains('{n: 0}')),
      isFalse,
    );
  });

  test('init() reloads a pre-seeded SharedPreferences list into the cache',
      () async {
    // Simulate a restart: the persisted store already holds prior events, the
    // in-memory cache is empty. init() must hydrate the cache from storage.
    final seeded = <String>[
      '07-07 10:00:00 Decryption failed | {msgId: 1}',
      '07-07 10:00:01 Reset session | {peer: 2}',
    ];
    SharedPreferences.setMockInitialValues({persistKey: seeded});
    await E2ePersistentDiag.clear();
    // clear() empties the persisted list too, so re-seed after clearing the
    // static cache to model a genuine cold start with the old prefs intact.
    SharedPreferences.setMockInitialValues({persistKey: seeded});

    await E2ePersistentDiag.init();

    expect(E2ePersistentDiag.entries, equals(seeded));
  });

  test('record writes through to SharedPreferences (raw getStringList lands)',
      () async {
    E2ePersistentDiag.record('Decryption failed', {'msgId': 99});
    E2ePersistentDiag.record('Reset session', {'peer': 3});

    // The write is fire-and-forget; let the microtask/event queue drain.
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(persistKey);
    expect(raw, isNotNull);
    expect(raw, hasLength(2));
    expect(raw!.first, contains('Decryption failed'));
    expect(raw.first, contains('99'));
    expect(raw.last, contains('Reset session'));
    expect(raw.last, contains('3'));
    // The persisted copy matches the in-memory cache view.
    expect(raw, equals(E2ePersistentDiag.entries));
  });

  test('entries getter returns an unmodifiable view', () {
    E2ePersistentDiag.record('evt', {'n': 1});
    expect(
      () => E2ePersistentDiag.entries.add('tampered'),
      throwsUnsupportedError,
    );
  });

  test('clear() empties both the cache and the persisted list', () async {
    E2ePersistentDiag.record('Decryption failed', {'msgId': 5});
    await Future<void>.delayed(Duration.zero);

    expect(E2ePersistentDiag.entries, isNotEmpty);

    await E2ePersistentDiag.clear();

    expect(E2ePersistentDiag.entries, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(persistKey), isEmpty);
  });
}
