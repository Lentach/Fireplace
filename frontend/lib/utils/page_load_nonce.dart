import 'dart:math';

/// A value generated once per page load (web) / process start (native).
///
/// If it changes between two reads in the SAME running app, the page reloaded —
/// used to disambiguate the iOS PWA mic re-prompt (reload vs per-getUserMedia).
final String kPageLoadNonce =
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '-${Random().nextInt(1 << 31).toRadixString(36)}';
