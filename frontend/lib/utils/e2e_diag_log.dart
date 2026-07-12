class E2eDiagLog {
  static const int kMaxEntries = 200;

  E2eDiagLog._();

  static final List<String> _entries = [];
  static final List<DateTime> _times = [];
  static final DateTime sessionStartedAt = DateTime.now();

  static void add(String step, Map<String, dynamic> data) {
    if (_entries.length >= kMaxEntries) {
      _entries.removeAt(0);
      _times.removeAt(0);
    }
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    _entries.add('$hh:$mm:$ss $step | $data');
    _times.add(now);
  }

  static List<String> get entries => List.unmodifiable(_entries);

  static List<String> since(Duration duration, {DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(duration);
    return [
      for (var i = 0; i < _entries.length; i++)
        if (_times[i].isAfter(cutoff)) _entries[i],
    ];
  }

  static void clear() {
    _entries.clear();
    _times.clear();
  }

  static List<String> groupedFailures(Iterable<String> entries) {
    final groups = <String, int>{};
    for (final entry in entries) {
      if (!entry.contains('FAIL') && !entry.contains('DECRYPT_DECISION')) {
        continue;
      }
      final peer =
          RegExp(
            r'(?:peerId|senderId|recipientId)[=: ]+([0-9]+)',
          ).firstMatch(entry)?.group(1) ??
          '?';
      final kind =
          RegExp(r'kind[=: ]+([A-Za-z_]+)').firstMatch(entry)?.group(1) ??
          'failure';
      final key = 'peer $peer · $kind';
      groups[key] = (groups[key] ?? 0) + 1;
    }
    return groups.entries
        .map((entry) => '${entry.key} · ${entry.value} messages')
        .toList(growable: false);
  }
}
