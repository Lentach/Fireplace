class E2eDiagLog {
  static const int kMaxEntries = 30;

  E2eDiagLog._();

  static final List<String> _entries = [];

  static void add(String step, Map<String, dynamic> data) {
    if (_entries.length >= kMaxEntries) _entries.removeAt(0);
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    _entries.add('$hh:$mm:$ss $step | $data');
  }

  static List<String> get entries => List.unmodifiable(_entries);

  static void clear() => _entries.clear();
}
