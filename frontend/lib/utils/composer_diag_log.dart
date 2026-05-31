/// In-memory ring buffer for the iOS-WebKit composer/keyboard diagnostics.
/// Mirrors [E2eDiagLog] but kept separate so the two logs don't interleave.
/// Viewed in Privacy & Safety (triple-tap the shield). In-memory only —
/// resets on restart.
///
/// TEMPORARY — remove with the composer diagnostics panel once the
/// keyboard-on action-panel bug is fixed.
class ComposerDiagLog {
  static const int kMaxEntries = 200;

  ComposerDiagLog._();

  static final List<String> _entries = [];

  static void add(String step, [Map<String, dynamic> data = const {}]) {
    if (_entries.length >= kMaxEntries) _entries.removeAt(0);
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    final ms = now.millisecond.toString().padLeft(3, '0');
    final suffix = data.isEmpty ? '' : ' | $data';
    _entries.add('$hh:$mm:$ss.$ms $step$suffix');
  }

  static List<String> get entries => List.unmodifiable(_entries);

  static void clear() => _entries.clear();
}
