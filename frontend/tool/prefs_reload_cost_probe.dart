// Headless browser probe: what does the 0.0.126 cross-engine coherence read
// actually COST on the chat-entry path?
//
// Same pattern as tool/session_cross_context_lock_probe.dart — compile to JS,
// serve, load in headless Chrome, read the result out of the DOM.
//
//   cd frontend
//   dart compile js tool/prefs_reload_cost_probe.dart -o build/prefs_probe/probe.js
//   python -m http.server 8766
//   chrome --headless=new --virtual-time-budget=180000 --dump-dom \
//     http://127.0.0.1:8766/tool/prefs_reload_cost_probe.html
//
// Title becomes PREFS_PROBE_DONE when the numbers are in <pre id="out">.
//
// WHAT IS BEING MEASURED
//
// EncryptionService.getDecryptedContent(id)          encryption_service.dart:633
//   -> _reloadPrefsForCrossContext(prefs)            encryption_service.dart:56
//        if (kIsWeb) await prefs.reload();
//   -> prefs.getString(key)
//
// SharedPreferences.reload() delegates to the web store's getAll()
// (shared_preferences_web-2.4.3:55), whose body is reproduced verbatim in
// [reloadLikeSharedPreferences] below: enumerate EVERY key in the origin's
// localStorage (src/keys_extension.dart:10), then getItem + jsonDecode each
// one carrying the `flutter.` prefix.
//
// messaging_provider.decrypt.dart:303 awaits that once PER history row whose
// plaintext is not already in the RAM cache. The persisted plaintext cache is
// capped at _decryptedContentCacheLimit = 2000 (encryption_service.dart:14).

import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const int _userId = 208;
const String _prefix = 'flutter.';

/// Mirrors the records EncryptionService.saveDecryptedContent persists. Text
/// rows are small; media rows carry base64 mediaKey/mediaIv/thumbHash and run
/// several hundred bytes. Real caches are a mix, so model both.
String _textBlob(int id) => jsonEncode(<String, Object>{
  'content':
      'message $id: the quick brown fox jumps over the lazy dog, and then '
      'says something a bit longer because real chat lines are not tiny',
});

String _mediaBlob(int id) => jsonEncode(<String, Object>{
  'content': '[encrypted]',
  'messageType': 'VOICE',
  'mediaUrl':
      'https://fireplace.ignorelist.com/media/msgs/'
      '0f8b2c1e-4a7d-4c3b-9e21-${id.toString().padLeft(12, '0')}.bin',
  'mediaDuration': 7,
  'mediaKey': base64Encode(List<int>.filled(32, 7)),
  'mediaIv': base64Encode(List<int>.filled(12, 3)),
  'mediaThumbHash': base64Encode(List<int>.filled(25, 9)),
});

String _contentKey(int id) => '${_prefix}e2e_${_userId}_decrypt_v1_$id';

/// Verbatim body of SharedPreferencesPlugin.getAllWithParameters — i.e. the
/// work one SharedPreferences.reload() does on web.
int reloadLikeSharedPreferences() {
  final storage = web.window.localStorage;
  final all = <String, Object>{};
  final length = storage.length;
  for (var i = 0; i < length; i++) {
    final key = storage.key(i);
    if (key == null || !key.startsWith(_prefix)) continue;
    final raw = storage.getItem(key);
    if (raw == null) continue;
    final decoded = jsonDecode(raw);
    if (decoded != null) all[key] = decoded as Object;
  }
  return all.length;
}
/// Verbatim body of SharedPreferencesAsyncWeb.getPreferences with NO allowList
/// — i.e. what `DualStorage.readAll()` costs on web. Note it does NOT filter by
/// prefix before reading: `_getAllowedKeys(allowList: null)` returns EVERY
/// localStorage key (shared_preferences_web-2.4.3:258-263), so every value in
/// the origin — Signal records AND the whole plaintext cache — is fetched and
/// json-decoded. Called by _pruneDecryptedContentCache on EVERY
/// saveDecryptedContent (encryption_service.dart:905).
int getAllLikeAsyncWeb() {
  final storage = web.window.localStorage;
  final all = <String, Object>{};
  final length = storage.length;
  final keys = <String>[];
  for (var i = 0; i < length; i++) {
    final k = storage.key(i);
    if (k != null) keys.add(k);
  }
  for (final key in keys) {
    final raw = storage.getItem(key);
    if (raw == null) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (_) {
      decoded = null;
    }
    if (decoded != null) all[key] = decoded;
  }
  return all.length;
}

/// Verbatim body of SharedPreferencesAsyncWeb.getString(key)
/// (shared_preferences_web-2.4.3:207-215 -> _readAllFromLocalStorage({key})).
/// The allowList filters AFTER `localStorage.keys` has materialised EVERY key,
/// so a SINGLE-key read is O(total keys in the origin). This is the path every
/// Signal session/identity/prekey load and store takes on web
/// (signal_stores.dart WebSignalKvStore.read/write -> AsyncKv).
String? getStringLikeAsyncWeb(String key) {
  final storage = web.window.localStorage;
  final length = storage.length;
  final allowed = <String>[];
  for (var i = 0; i < length; i++) {
    final k = storage.key(i);
    if (k != null && k == key) allowed.add(k);
  }
  for (final k in allowed) {
    final raw = storage.getItem(k);
    if (raw == null) continue;
    try {
      return jsonDecode(raw) as String?;
    } on FormatException catch (_) {
      return null;
    }
  }
  return null;
}

/// Recreate a realistic origin store.
///
/// - [records] plaintext-cache entries, 1 in 5 a keyed media row;
/// - 40 raw-replay entries holding full ciphertext
///   (_rawDecryptedContentCacheLimit = 40, encryption_service.dart:867);
/// - Signal identity/prekey/session records, written UNPREFIXED by
///   SharedPreferencesAsyncWeb, so they inflate the key enumeration but skip
///   the decode loop. A serialized SessionRecord is multi-KB.
void _seed(int records) {
  final storage = web.window.localStorage;
  storage.clear();

  final sessionRecord = base64Encode(List<int>.filled(2600, 42));
  final preKeyRecord = base64Encode(List<int>.filled(140, 11));
  for (var i = 0; i < 8; i++) {
    storage.setItem('sig_session_${100 + i}_1', sessionRecord);
  }
  for (var i = 0; i < 110; i++) {
    storage.setItem('sig_prekey_$i', preKeyRecord);
  }
  storage.setItem(
    'sig_identity_key_pair',
    base64Encode(List<int>.filled(96, 5)),
  );
  storage.setItem('sig_registration_id', '12345');

  final ciphertext = '2:${base64Encode(List<int>.filled(420, 23))}';
  for (var i = 0; i < 40; i++) {
    storage.setItem(
      '${_prefix}e2e_${_userId}_decrypt_raw_v1_$i',
      jsonEncode(<String, Object>{
        'ciphertext': ciphertext,
        'plaintext': jsonEncode(<String, Object>{'content': 'replayed $i'}),
      }),
    );
  }

  for (var i = 0; i < records; i++) {
    storage.setItem(
      _contentKey(i),
      i % 5 == 0 ? _mediaBlob(i) : _textBlob(i),
    );
  }
}

int _microsOf(void Function() body, {int reps = 1}) {
  final sw = Stopwatch()..start();
  for (var i = 0; i < reps; i++) {
    body();
  }
  sw.stop();
  return sw.elapsedMicroseconds ~/ reps;
}

String _pad(int v, int w) => v.toString().padLeft(w);

void main() {
  final out = StringBuffer();

  out.writeln('== one SharedPreferences.reload() vs stored plaintext records ==');
  for (final records in <int>[0, 100, 500, 1000, 2000]) {
    _seed(records);
    reloadLikeSharedPreferences(); // warm
    final us = _microsOf(reloadLikeSharedPreferences, reps: 10);
    out.writeln(
      'cached rows=${_pad(records, 4)}   '
      'one reload=${(us / 1000).toStringAsFixed(2)} ms',
    );
  }

  out.writeln();
  out.writeln('== every Signal store read/write pays a FULL key enumeration ==');
  out.writeln('(SharedPreferencesAsyncWeb.getString filters the allowList');
  out.writeln(' AFTER materialising localStorage.keys — one key still costs O(all))');
  for (final records in <int>[0, 500, 2000]) {
    _seed(records);
    getStringLikeAsyncWeb('sig_session_100_1'); // warm
    final us = _microsOf(
      () => getStringLikeAsyncWeb('sig_session_100_1'),
      reps: 50,
    );
    out.writeln(
      'cached rows=${_pad(records, 4)}   '
      'one Signal key read=${(us / 1000).toStringAsFixed(3)} ms',
    );
  }

  out.writeln();
  out.writeln('== DualStorage.readAll(), run once per saveDecryptedContent ==');
  out.writeln('(_pruneDecryptedContentCache, encryption_service.dart:905 —');
  out.writeln(' decodes EVERY localStorage value, matches ZERO decrypted_ keys)');
  for (final records in <int>[0, 500, 2000]) {
    _seed(records);
    getAllLikeAsyncWeb(); // warm
    final us = _microsOf(getAllLikeAsyncWeb, reps: 10);
    out.writeln(
      'cached rows=${_pad(records, 4)}   '
      'one readAll=${(us / 1000).toStringAsFixed(2)} ms',
    );
  }

  out.writeln();
  out.writeln('== chat entry, plaintext cache at its 2000-row cap ==');
  out.writeln('CURRENT  (getDecryptedContent reloads per message):');
  _seed(2000);
  reloadLikeSharedPreferences();
  final current = <int, int>{};
  for (final history in <int>[50, 100, 200, 400]) {
    final us = _microsOf(() {
      for (var i = 0; i < history; i++) {
        reloadLikeSharedPreferences();
        web.window.localStorage.getItem(_contentKey(i));
      }
    });
    current[history] = us;
    out.writeln(
      '  history=${_pad(history, 3)} rows   '
      'main-thread=${(us / 1000).toStringAsFixed(1)} ms   '
      'per-row=${(us / history / 1000).toStringAsFixed(2)} ms',
    );
  }

  out.writeln();
  out.writeln('CONTROL  (one reload for the whole pass, then N plain reads):');
  final control = <int, int>{};
  for (final history in <int>[50, 100, 200, 400]) {
    final us = _microsOf(() {
      reloadLikeSharedPreferences();
      for (var i = 0; i < history; i++) {
        web.window.localStorage.getItem(_contentKey(i));
      }
    });
    control[history] = us;
    out.writeln(
      '  history=${_pad(history, 3)} rows   '
      'main-thread=${(us / 1000).toStringAsFixed(1)} ms   '
      'per-row=${(us / history / 1000).toStringAsFixed(3)} ms',
    );
  }

  out.writeln();
  out.writeln('== attributable to the per-message reload ==');
  for (final history in <int>[50, 100, 200, 400]) {
    final delta = (current[history]! - control[history]!) / 1000;
    final ratio = current[history]! / control[history]!.clamp(1, 1 << 30);
    out.writeln(
      '  history=${_pad(history, 3)} rows   '
      '+${delta.toStringAsFixed(1)} ms   (${ratio.toStringAsFixed(0)}x)',
    );
  }

  web.window.localStorage.clear();

  final pre = web.document.getElementById('out');
  if (pre != null) pre.textContent = out.toString();
  web.document.title = 'PREFS_PROBE_DONE';
  web.console.log(out.toString().toJS);
}
