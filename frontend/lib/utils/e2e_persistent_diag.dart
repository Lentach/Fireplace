import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'e2e_diag_log.dart';

/// Durable mirror of FAILURE-CLASS E2E diagnostic events.
///
/// The live [E2eDiagLog] ring is 200 in-memory entries — under iOS
/// resume/reconnect churn it evicts fast, and it is wiped on every app
/// restart. That is why field `[Decryption failed]` reports arrive with no
/// failure events in the copied log: they had already scrolled out. This
/// store keeps a small capped tail of ONLY failure/reset events in
/// persistent storage (web localStorage via SharedPreferences, mobile native)
/// so they survive eviction AND restarts — for "monitor and come back later"
/// field diagnosis.
///
/// Success-path chatter stays out on purpose: this must remain tiny and
/// high-signal. Records also flow into the live ring so both panels agree.
class E2ePersistentDiag {
  E2ePersistentDiag._();

  /// Public so the native content store can EXCLUDE this key from its legacy
  /// drain by reference, not by a stringly copy that would rot on rename.
  /// (It is a StringList the drain could not carry anyway; the exclusion is
  /// belt and braces on top of the type guard.)
  // Not a secret: a SharedPreferences key NAME. gitleaks:allow
  static const String storageKey = 'e2e_diag_persist_v1'; // gitleaks:allow
  static const String _key = storageKey;
  static const int kMaxEntries = 80;

  static SharedPreferences? _prefs;
  static final List<String> _cache = [];

  /// Load persisted entries. Call once before `runApp`; diagnostics must never
  /// block or crash startup.
  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _cache
        ..clear()
        ..addAll(_prefs?.getStringList(_key) ?? const []);
    } catch (_) {
      // Ignore — a missing diagnostic store is never fatal.
    }
  }

  /// Record a failure-class event: mirror into the live ring (with the same
  /// debug print as `_e2eFlowLog`) AND persist a date-stamped copy.
  static void record(String step, [Map<String, dynamic>? data]) {
    final payload = data ?? const {};
    E2eDiagLog.add(step, payload);
    if (kDebugMode) debugPrint('[E2E-FLOW] $step | $payload');

    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    // Date-stamped: these survive restarts, so a bare clock time is ambiguous.
    final line =
        '${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)} $step | $payload';
    _cache.add(line);
    while (_cache.length > kMaxEntries) {
      _cache.removeAt(0);
    }
    // Fire-and-forget: the failure path must never await storage. `.ignore()`
    // swallows a rejected write (quota / private-mode web) without leaking an
    // unhandled async error.
    _prefs?.setStringList(_key, _cache).ignore();
  }

  /// [record], except a repeat of an event ALREADY in the durable cache is
  /// routed to the ring only (full payload unchanged): the durable log is
  /// cap-80 and noise evicts evidence — one field row re-burning a durable
  /// slot per boot made the owner's dump ~90% repeats of known-terminal rows
  /// (design `terminal-duplicate-retirement.md` §4).
  ///
  /// A line is a repeat when it contains ` $step | ` and EVERY [matchAll]
  /// substring. Callers pass substrings WITH trailing delimiters (e.g.
  /// `'{msgId: 1910,'`) so an id can never prefix-match a longer one. The
  /// dedupe state IS the cache: eviction past [kMaxEntries] or a manual clear
  /// re-arms the event, so nothing is ever permanently suppressed.
  static void recordDeduped(
    String step,
    Map<String, dynamic> data, {
    required List<String> matchAll,
  }) {
    final isRepeat = _cache.any(
      (line) => line.contains(' $step | ') && matchAll.every(line.contains),
    );
    if (isRepeat) {
      E2eDiagLog.add(step, data);
      if (kDebugMode) debugPrint('[E2E-FLOW] $step | $data (durable-deduped)');
      return;
    }
    record(step, data);
  }

  static List<String> get entries => List.unmodifiable(_cache);

  static Future<void> clear() async {
    _cache.clear();
    try {
      await _prefs?.setStringList(_key, const []);
    } catch (_) {}
  }
}
