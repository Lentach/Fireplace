import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/services/encryption_service.dart';
import 'package:fireplace/services/server_clock.dart';
import 'package:fireplace/utils/e2e_diag_log.dart';

/// Expiry-sweep observability: `sweepDestroyablePlaintext` must leave a RING
/// trace on success, not only on failure. Before this, a sweep that destroyed
/// plaintext — the only copy of a message — was indistinguishable in a diag
/// dump from a sweep that never ran, and "the sweep is alive but found
/// nothing" was invisible entirely.
///
/// Channel rule under test: the ring (`E2eDiagLog`), NEVER the cap-80 durable
/// log — success is routine, and durable noise evicts failure evidence (the
/// exact class 0.1.6 cleaned up). Failure paths keep their existing
/// `PLAINTEXT_PURGE_INCOMPLETE` / `PLAINTEXT_PURGE_LOST` channels.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EncryptionService service;
  late EncryptionProvider provider;

  List<String> sweepEntries() => E2eDiagLog.entries
      .where((e) => e.contains('PLAINTEXT_SWEEP'))
      .toList(growable: false);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    E2eDiagLog.clear();
    ServerClock.instance.resetForTest();
    service = EncryptionService();
    await service.initialize(42);
    provider = EncryptionProvider(service: service);
  });

  tearDown(() {
    ServerClock.instance.resetForTest();
    E2eDiagLog.clear();
  });

  group('sweepDestroyablePlaintext ring diagnostics', () {
    test('a destroying sweep logs counts, removed, and the condemned ids',
        () async {
      final serverNow = DateTime.now().toUtc();
      ServerClock.instance.observe(serverNow);
      await service.saveDecryptedContent(
        101,
        {'content': 'long expired'},
        expiresAt: serverNow.subtract(const Duration(minutes: 6)),
      );
      await service.saveDecryptedContent(
        102,
        {'content': 'also expired'},
        expiresAt: serverNow.subtract(const Duration(minutes: 7)),
      );
      await service.saveDecryptedContent(103, {'content': 'never expires'});

      await provider.sweepDestroyablePlaintext();

      final entries = sweepEntries();
      expect(entries, hasLength(1));
      expect(entries.single, contains('expired: 2'));
      expect(entries.single, contains('retired: 0'));
      expect(entries.single, contains('removed: 2'));
      expect(entries.single, contains('ids: [101, 102]'));
      // And the sweep actually destroyed exactly the condemned rows.
      expect(await service.getDecryptedContent(101), isNull);
      expect(await service.getDecryptedContent(102), isNull);
      expect((await service.getDecryptedContent(103))?['content'],
          'never expires');
    });

    test('an empty sweep logs zero ONCE, consecutive empty ticks stay silent',
        () async {
      ServerClock.instance.observe(DateTime.now().toUtc());
      await service.saveDecryptedContent(201, {'content': 'live'});

      await provider.sweepDestroyablePlaintext();
      await provider.sweepDestroyablePlaintext();
      await provider.sweepDestroyablePlaintext();

      final entries = sweepEntries();
      expect(entries, hasLength(1),
          reason: 'the sweep ticks every minute; per-tick zero entries would '
              'churn the 200-entry ring and evict real evidence');
      expect(entries.single, contains('expired: 0'));
      expect(entries.single, contains('retired: 0'));
    });

    test('the zero entry re-arms after a destroying sweep', () async {
      final serverNow = DateTime.now().toUtc();
      ServerClock.instance.observe(serverNow);

      // Tick 1-2: nothing due → one zero entry.
      await provider.sweepDestroyablePlaintext();
      await provider.sweepDestroyablePlaintext();
      // A message expires → tick 3 destroys it.
      await service.saveDecryptedContent(
        301,
        {'content': 'expires'},
        expiresAt: serverNow.subtract(const Duration(minutes: 6)),
      );
      await provider.sweepDestroyablePlaintext();
      // Tick 4-5: back to nothing due → exactly one more zero entry.
      await provider.sweepDestroyablePlaintext();
      await provider.sweepDestroyablePlaintext();

      final entries = sweepEntries();
      expect(entries, hasLength(3));
      expect(entries[0], contains('expired: 0'));
      expect(entries[1], contains('expired: 1'));
      expect(entries[2], contains('expired: 0'));
    });

    test('an unconfirmable clock logs NOTHING — silence is the fail-closed '
        'contract, not a missing diag', () async {
      // No ServerClock observation: the sweep must hold and stay silent
      // (root CLAUDE.md §7 documents this silence as deliberate).
      await service.saveDecryptedContent(
        401,
        {'content': 'expired but unconfirmable'},
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );

      await provider.sweepDestroyablePlaintext();

      expect(sweepEntries(), isEmpty);
      expect((await service.getDecryptedContent(401))?['content'],
          'expired but unconfirmable');
    });

    test('a sweep condemning more than the cap truncates the id list',
        () async {
      final serverNow = DateTime.now().toUtc();
      ServerClock.instance.observe(serverNow);
      for (var id = 1; id <= 35; id++) {
        await service.saveDecryptedContent(
          id,
          {'content': 'msg $id'},
          expiresAt: serverNow.subtract(const Duration(minutes: 6)),
        );
      }

      await provider.sweepDestroyablePlaintext();

      final entries = sweepEntries();
      expect(entries, hasLength(1));
      expect(entries.single, contains('expired: 35'));
      expect(entries.single, contains('idsTruncated: 5'));
      expect(entries.single, isNot(contains(' 31,')),
          reason: 'ids are sorted and capped at 30');
    });
  });
}
