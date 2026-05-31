import 'web_diag_probe_stub.dart'
    if (dart.library.html) 'web_diag_probe_web.dart' as impl;

/// Live web-layer diagnostics for the iOS-WebKit composer keyboard bug.
/// Returns an empty map off-web.
///
/// TEMPORARY — remove together with [ComposerDiagnosticsOverlay] once the
/// keyboard-on action-panel bug is fixed.
Map<String, String> readWebDiagProbe() => impl.readWebDiagProbe();
