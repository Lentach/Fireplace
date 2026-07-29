import 'dart:io';
import 'dart:typed_data';

import '../audio_cache_store.dart';
import 'sealed_audio_codec.dart';

/// Rotation pass over the decrypted voice-note cache: re-seals every file
/// whose header names a retiring content key, so the rotation may destroy
/// those keys without bricking any voice note.
///
/// Returns whether the cache is provably clean of the retiring kids. Files
/// that are NOT sealed (legacy plaintext `.audio`/`.m4a`) are left alone here
/// — they hold no reference to any key, so key destruction cannot hurt them;
/// they get sealed when the audio write path next touches them.
///
/// Replacement is write-to-temp + atomic rename, so a kill mid-reseal leaves
/// either the old file (still sealed under the retiring key — the rotation
/// aborts and retries, key survives) or the new one. Never a torn file.
Future<bool> resealAudioCacheFiles(
  Map<String, Uint8List> retiringKeys,
  String newKid,
  Uint8List newKey,
) async {
  final Directory? dir;
  try {
    dir = await AudioCacheStore.directory();
  } catch (_) {
    return false;
  }
  if (dir == null) return true; // web / no cache: nothing to re-seal
  if (!await dir.exists()) return true;

  var clean = true;
  try {
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      try {
        final bytes = await entry.readAsBytes();
        final kid = SealedAudioCodec.kidOf(bytes);
        if (kid == null) continue; // legacy plaintext or foreign file
        final retiringKey = retiringKeys[kid];
        if (retiringKey == null) continue; // already on a surviving key
        final plain = await SealedAudioCodec.unseal(
          bytes: bytes,
          keyBytes: retiringKey,
        );
        if (plain == null) {
          // Unreadable under the key that allegedly sealed it: corrupt, and
          // equally unreadable whether the key lives or dies. Not a reason
          // to keep the key alive.
          continue;
        }
        final resealed = await SealedAudioCodec.seal(
          kid: newKid,
          keyBytes: newKey,
          plaintext: plain,
        );
        final tmp = File('${entry.path}.reseal');
        await tmp.writeAsBytes(resealed, flush: true);
        await tmp.rename(entry.path);
      } catch (_) {
        // This file may still need the retiring key; the rotation must not
        // destroy it. Abort-and-retry semantics, same as a refused DB batch.
        clean = false;
      }
    }
  } catch (_) {
    return false;
  }
  return clean;
}
