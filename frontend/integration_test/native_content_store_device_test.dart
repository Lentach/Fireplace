import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fireplace/services/auth_token_store.dart';
import 'package:fireplace/services/encryption/audio_reseal.dart';
import 'package:fireplace/services/encryption/content_db.dart';
import 'package:fireplace/services/encryption/content_key_manager.dart';
import 'package:fireplace/services/encryption/content_kv_opener_stub.dart'
    if (dart.library.io) 'package:fireplace/services/encryption/content_kv_opener_io.dart';
import 'package:fireplace/services/encryption/native_content_store.dart';
import 'package:fireplace/services/encryption/sealed_audio_codec.dart';
import 'package:fireplace/services/secure_kv.dart';
import 'package:fireplace/utils/e2e_persistent_diag.dart';
import 'package:fireplace/widgets/audio/voice_player_native.dart';

/// ON-DEVICE acceptance for the Phase 2 encrypted store: real Android
/// Keystore, the real SQLCipher `.so` from the APK, real webcrypto.
///
///   cd frontend && flutter test integration_test -d `emulator id`
///
/// This is the executable half of the acceptance criteria in
/// docs/plans/2026-07-29-android-phase2-handoff.md; the remaining manual half
/// is the owner smoke checklist (voice play/seek by hand, push, etc.).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final runId = DateTime.now().millisecondsSinceEpoch;

  ContentKeyManager realKeys() => ContentKeyManager(
    const FlutterSecureStorageKv(
      FlutterSecureStorage(webOptions: WebOptions(dbName: 'FireplaceE2E')),
    ),
  );

  test('platform opener arms the ENCRYPTED store on Android', () async {
    expect(Platform.isAndroid, isTrue, reason: 'run this on Android');
    final kv = await openPlatformContentKv();
    // A prefs fallback here means SQLCipher/keystore arming failed on a
    // healthy device — exactly what must never happen silently.
    expect(kv, isA<NativeContentStore>());
    expect((kv as NativeContentStore).debugActiveKid, isNotEmpty);
  });

  test('sealed record: plaintext never appears in the DB file bytes',
      () async {
    final kv = await openPlatformContentKv() as NativeContentStore;
    final marker = 'FIREPLACE_MARKER_$runId';
    final ok = await kv.setString(
      'e2e_990_decrypted_$runId',
      '{"content":"$marker"}',
    );
    expect(ok, isTrue);
    expect(kv.getString('e2e_990_decrypted_$runId'), contains(marker));

    final db = await DriftRecordDb.databaseFile();
    final markerBytes = Uint8List.fromList(marker.codeUnits);
    for (final path in [db.path, '${db.path}-wal']) {
      final f = File(path);
      if (!await f.exists()) continue;
      final bytes = await f.readAsBytes();
      expect(_indexOf(bytes, markerBytes), -1,
          reason: 'plaintext leaked into $path');
    }
    // SQLCipher file: the standard SQLite magic must NOT be readable.
    final head = await File(db.path).openRead(0, 16).first;
    expect(String.fromCharCodes(head).startsWith('SQLite format 3'), isFalse,
        reason: 'DB file is not encrypted');
  });

  test('JWT tokens land in Keystore-backed storage, never in prefs XML',
      () async {
    final store = AuthTokenStore();
    await store.write(access: 'itest-access-$runId', refresh: 'itest-r-$runId');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('jwt_token'), isNull);
    expect(prefs.getString('refresh_token'), isNull);
    final read = await store.read();
    expect(read.access, 'itest-access-$runId');
    expect(read.refresh, 'itest-r-$runId');
    await store.clear();
    final cleared = await store.read();
    expect(cleared.access, isNull);
  });

  test('legacy prefs drain: seeded e2e_ keys are sealed then deleted',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final legacyKey = 'e2e_991_decrypted_$runId';
    await prefs.setString(legacyKey, '{"content":"legacy-$runId"}');

    // A store opened AFTER the legacy write (i.e. the next launch of a
    // pre-Phase-2 install). Fresh components, same real DB/keystore.
    final dbKey = await realKeys().dbKeyHex();
    expect(dbKey, isNotNull);
    final store2 = await NativeContentStore.open(
      db: await DriftRecordDb.open(dbKeyHex: dbKey!.hex),
      keys: realKeys(),
      legacyPrefs: prefs,
      audioResealer: resealAudioCacheFiles,
    );
    expect(store2.getString(legacyKey), '{"content":"legacy-$runId"}');
    await store2.debugDrainNow();
    expect(prefs.containsKey(legacyKey), isFalse,
        reason: 'drain must delete the migrated prefs key');
    expect(store2.getString(legacyKey), '{"content":"legacy-$runId"}');
    await store2.close();
  });

  test('purge stamps rotation; rotation destroys the old key in Keystore',
      () async {
    final keys = realKeys();
    final dbKey = await keys.dbKeyHex();
    final store = await NativeContentStore.open(
      db: await DriftRecordDb.open(dbKeyHex: dbKey!.hex),
      keys: keys,
      legacyPrefs: await SharedPreferences.getInstance(),
      audioResealer: resealAudioCacheFiles,
    );
    final oldKid = store.debugActiveKid;
    await store.setString('e2e_992_decrypted_$runId', '{"c":"victim"}');
    expect(await store.remove('e2e_992_decrypted_$runId'), isTrue);
    expect(store.rotationPending, isTrue);

    await store.rotateNow();
    expect(store.rotationPending, isFalse);
    expect(store.debugActiveKid, isNot(oldKid));
    final inventory = await keys.inventory();
    expect(inventory, isNotNull);
    expect(inventory!.keys.containsKey(oldKid), isFalse,
        reason: 'retired key must be GONE from the real Keystore-backed '
            'storage — that destruction IS the shred');
    await store.close();
  });

  test('sealed audio codec round-trips on the real native webcrypto',
      () async {
    final key = Uint8List.fromList(List.generate(32, (i) => (i * 7) & 0xff));
    final audio = Uint8List.fromList(List.generate(8192, (i) => i & 0xff));
    final sealed = await SealedAudioCodec.seal(
      kid: 'device-k1',
      keyBytes: key,
      plaintext: audio,
    );
    expect(SealedAudioCodec.kidOf(sealed), 'device-k1');
    expect(await SealedAudioCodec.unseal(bytes: sealed, keyBytes: key), audio);
    final wrong = Uint8List.fromList(List.generate(32, (i) => 255 - i));
    expect(
        await SealedAudioCodec.unseal(bytes: sealed, keyBytes: wrong), isNull);
  });

  test('in-memory audio source: load, duration, seek via the range proxy',
      () async {
    // A synthesized 2-second PCM WAV: real enough for ExoPlayer to parse,
    // fully deterministic, no asset needed. This drives the exact
    // StreamAudioSource path sealed voice notes play through.
    final wav = _pcmWav(seconds: 2, sampleRate: 8000);
    final player = NativeVoicePlayer();
    try {
      await player.setAudioBytes(wav);
      final duration = player.duration;
      expect(duration, isNotNull);
      expect((duration!.inMilliseconds - 2000).abs() < 150, isTrue,
          reason: 'duration $duration should be ~2s');
      // Seek exercises ranged requests against _BytesAudioSource.
      await player.seek(const Duration(seconds: 1));
      debugPrint('audio source ok: duration=$duration');
    } finally {
      await player.dispose();
    }
  });

  // LAST on purpose: it destroys every content key in the real Keystore, so
  // any record an earlier test sealed becomes unreadable after it runs.
  test('content-key loss: history retires, no crash, no [Decryption failed]',
      () async {
    final keys = realKeys();
    final dbKey = await keys.dbKeyHex();
    final store = await NativeContentStore.open(
      db: await DriftRecordDb.open(dbKeyHex: dbKey!.hex),
      keys: keys,
      legacyPrefs: await SharedPreferences.getInstance(),
      audioResealer: resealAudioCacheFiles,
    );
    const uid = 993;
    final id = runId % 100000;
    await store.setString('e2e_${uid}_decrypted_$id', '{"c":"doomed"}');
    await store.close();

    // Simulate the loss the spec's acceptance #3 describes: the Keystore
    // entries are gone while the encrypted DB file survives intact.
    final before = await keys.inventory();
    expect(before, isNotNull);
    for (final kid in before!.keys.keys) {
      expect(await keys.destroyContentKey(kid), isTrue);
    }

    await E2ePersistentDiag.init();
    final reopened = await NativeContentStore.open(
      db: await DriftRecordDb.open(dbKeyHex: dbKey.hex),
      keys: keys,
      legacyPrefs: await SharedPreferences.getInstance(),
      audioResealer: resealAudioCacheFiles,
    );
    // Opened, not crashed, and NOT degraded to a plaintext session.
    expect(reopened.debugActiveKid, isNotEmpty);
    // The record is not served as content — the UI must never hand a consumed
    // ciphertext to live decrypt and end up at a terminal [Decryption failed].
    expect(reopened.getString('e2e_${uid}_decrypted_$id'), isNull);
    // It is retired instead: that is what renders "no longer stored".
    final retired =
        jsonDecode(reopened.getString('e2e_${uid}_retired_v1')!) as List;
    expect(retired, contains(id));
    expect(
      E2ePersistentDiag.entries.any((e) => e.contains('CONTENT_KEY_LOST')),
      isTrue,
      reason: 'field diagnostics must name the loss',
    );
    // New writes still work, under a freshly armed key.
    expect(await reopened.setString('e2e_${uid}_decrypted_1', '{"c":"new"}'),
        isTrue);
    expect(reopened.getString('e2e_${uid}_decrypted_1'), '{"c":"new"}');
    await reopened.close();
  });
}

int _indexOf(Uint8List haystack, Uint8List needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

Uint8List _pcmWav({required int seconds, required int sampleRate}) {
  final samples = seconds * sampleRate;
  final dataLen = samples * 2;
  final b = BytesBuilder();
  void u32(int v) =>
      b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  b.add('RIFF'.codeUnits);
  u32(36 + dataLen);
  b.add('WAVE'.codeUnits);
  b.add('fmt '.codeUnits);
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  b.add('data'.codeUnits);
  u32(dataLen);
  for (var i = 0; i < samples; i++) {
    // Quiet 440 Hz-ish square wave; content is irrelevant, parseability is.
    u16(((i ~/ 9) % 2 == 0) ? 800 : -800 & 0xffff);
  }
  return b.toBytes();
}
