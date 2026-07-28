import 'package:flutter/foundation.dart';

/// Best-effort LOWER BOUND on the server's clock.
///
/// WHY THIS EXISTS. Destroying expired plaintext destroys the ONLY copy of a
/// message: the server keeps ciphertext whose Double Ratchet message key was
/// consumed at first decrypt, so nothing can bring it back — not the server,
/// not a re-decrypt (that lands on DuplicateMessage). Meanwhile the client
/// decides expiry with `DateTime.now()` while the server decides with
/// `CURRENT_TIMESTAMP` and hard-deletes on a per-minute cron. A device whose
/// wall clock runs fast would destroy plaintext for messages that are still
/// live server-side: permanent data loss caused by a wrong local clock.
///
/// So the destroy gate never reads the local wall clock. It reads this, which
/// is built to lag rather than lead, and to fail closed:
///
///  * Observations are server-stamped instants only.
///  * Forward progress comes from a monotonic [Stopwatch] measuring ELAPSED
///    time, never from the local absolute clock. A wrong wall clock is common;
///    a wrong tick rate is not. On web a suspended tab under-counts elapsed
///    time, which makes the estimate lag — the safe direction.
///  * One-way network latency makes every observation slightly stale, which
///    also makes the estimate lag.
///  * [estimatedNow] returns null once an observation is too old to trust.
///    Null means "cannot confirm", NEVER "not yet expired". Callers hold.
///
/// Against a backend that does not send `serverTime` there is simply no
/// observation, [estimatedNow] stays null, and nothing is ever destroyed on
/// expiry. Degrading to the old behaviour — plaintext lingers, but nothing is
/// lost — is the deliberate choice.
class ServerClock {
  ServerClock();

  /// Process-wide instance. The server's clock is one global fact, and the
  /// observers (socket ack, message payloads) are far from the consumers (the
  /// expiry sweep); threading an instance through both would buy nothing.
  static ServerClock instance = ServerClock();

  /// How far a single observation may be projected forward before it is
  /// refused. Bounds two things: a suspended tab resuming with a stale base,
  /// and — where `Stopwatch` degrades to the wall clock, as it can on web —
  /// the amount of false progress a mid-session clock change can inject.
  static const Duration maxExtrapolation = Duration(minutes: 30);

  DateTime? _observed;
  final Stopwatch _since = Stopwatch();

  /// Feed a server-stamped instant.
  ///
  /// The newest observation always wins, including one that moves the estimate
  /// BACKWARDS. That is not a bug: a lower estimate only delays destruction,
  /// and delay is the safe failure mode here. Guarding monotonicity would mean
  /// carrying an extrapolation forward as if it were evidence.
  void observe(DateTime serverTime) {
    _observed = serverTime.toUtc();
    _since
      ..reset()
      ..start();
  }

  /// Parse an ISO-8601 instant off the wire and [observe] it. Ignores anything
  /// unparseable — a malformed stamp must not become a confident clock.
  void observeIso(Object? iso) {
    if (iso is! String) return;
    final parsed = DateTime.tryParse(iso);
    if (parsed != null) observe(parsed);
  }

  /// Estimated server time, or null when no observation is fresh enough.
  ///
  /// A null answer is a refusal, not a zero. Never substitute `DateTime.now()`.
  DateTime? get estimatedNow {
    final base = _observed;
    if (base == null) return null;
    final elapsed = _since.elapsed;
    if (elapsed > maxExtrapolation) return null;
    return base.add(elapsed);
  }

  /// True when the clock can currently answer. Callers that need the value
  /// should just null-check [estimatedNow]; this exists for diagnostics.
  bool get canConfirm => estimatedNow != null;

  @visibleForTesting
  void resetForTest() {
    _observed = null;
    _since
      ..reset()
      ..stop();
  }
}
