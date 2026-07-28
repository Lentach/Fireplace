import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Owns the on-disk cache of DECRYPTED voice notes.
///
/// Native only. A played voice note is written to
/// `<app documents>/audio_cache/<messageId>.audio` in the clear, so a message
/// purge that ignores this directory leaves readable audio behind — and the
/// documents directory is swept into iCloud / Android auto-backup, which
/// carries it off the device entirely. Web never writes here (audio stays in
/// memory), so every entry point returns early under [kIsWeb].
///
/// This is a service rather than state on the playback widget so the filename
/// convention has exactly ONE owner: the legacy `.m4a` extension is still on
/// disk for older messages, and a purge that only knew about `.audio` would
/// silently miss them.
class AudioCacheStore {
  const AudioCacheStore._();

  static const String _dirName = 'audio_cache';

  /// Current and legacy filenames for [messageId]. Both are checked on read
  /// and both are destroyed on purge.
  static List<String> fileNamesFor(int messageId) => [
    '$messageId.audio',
    '$messageId.m4a',
  ];

  /// The cache directory, or null on web.
  static Future<Directory?> directory() async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/$_dirName');
  }

  /// The existing cached file for [messageId], or null.
  static Future<File?> find(int messageId) async {
    final dir = await directory();
    if (dir == null) return null;
    for (final name in fileNamesFor(messageId)) {
      final file = File('${dir.path}/$name');
      if (file.existsSync()) return file;
    }
    return null;
  }

  /// Destination for a freshly downloaded voice note, creating the directory.
  /// Null on web.
  static Future<File?> createTarget(int messageId) async {
    final dir = await directory();
    if (dir == null) return null;
    await dir.create(recursive: true);
    return File('${dir.path}/$messageId.audio');
  }

  /// Destroy the cached audio for [messageIds].
  ///
  /// Returns the ids whose file could not be removed and may still hold
  /// readable audio. Callers folding this into a purge result MUST treat a
  /// non-empty return as an incomplete purge.
  ///
  /// Never throws. It is called from a fire-and-forget purge, so an escaping
  /// exception would become an unhandled async error and abandon the rest of
  /// the work. Web returns empty because nothing was ever written there; a
  /// failure to even resolve the directory returns EVERY id, because at that
  /// point we cannot say whether decrypted audio is still on disk and
  /// reporting success would be a guess.
  static Future<Set<int>> remove(Iterable<int> messageIds) async {
    final ids = messageIds.toSet();
    if (kIsWeb || ids.isEmpty) return <int>{};

    final Directory dir;
    try {
      final resolved = await directory();
      if (resolved == null) return <int>{};
      dir = resolved;
    } catch (_) {
      return ids;
    }

    final failed = <int>{};
    for (final id in ids) {
      for (final name in fileNamesFor(id)) {
        try {
          final file = File('${dir.path}/$name');
          if (file.existsSync()) await file.delete();
        } catch (_) {
          failed.add(id);
        }
      }
    }
    return failed;
  }

  /// Destroy every cached voice note. Returns how many files were removed.
  static Future<int> clear() async {
    final dir = await directory();
    if (dir == null || !dir.existsSync()) return 0;
    var deleted = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) deleted++;
    }
    await dir.delete(recursive: true);
    return deleted;
  }
}
