import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../utils/composer_probe.dart';

/// Dev testing tool: on-screen readout of the visualViewport-derived keyboard
/// inset (what now drives the composer position) vs. Flutter's unreliable
/// `MediaQuery.viewInsets.bottom`. Off by default so real users never see it;
/// toggled at runtime by long-pressing the chat app-bar title (mobile web).
///
/// To remove entirely: delete this file and its usage in
/// `chat_composer_viewport.dart`.
final ValueNotifier<bool> composerDiagOverlayEnabled =
    ValueNotifier<bool>(false);

/// Flip the overlay on/off. No-op effect off web (overlay never mounts).
void toggleComposerDiagOverlay() =>
    composerDiagOverlayEnabled.value = !composerDiagOverlayEnabled.value;

class ComposerDiagnosticsOverlay extends StatefulWidget {
  const ComposerDiagnosticsOverlay({
    super.key,
    required this.flutterInset,
    required this.computedInset,
    required this.debouncedInset,
  });

  /// `MediaQuery.viewInsets.bottom` — Flutter's keyboard inset (reads 0 on iOS).
  final double flutterInset;

  /// visualViewport-derived inset (null when the source is inactive).
  final double? computedInset;

  /// What the composer is actually `Positioned(bottom:)` at after debounce.
  final double debouncedInset;

  /// True only where the overlay can run (web). Actual visibility is further
  /// gated at runtime by [composerDiagOverlayEnabled].
  static bool get isAvailable => kIsWeb;

  @override
  State<ComposerDiagnosticsOverlay> createState() =>
      _ComposerDiagnosticsOverlayState();
}

class _ComposerDiagnosticsOverlayState
    extends State<ComposerDiagnosticsOverlay> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      'kbInset(vv):  ${widget.computedInset?.round() ?? '-'}',
      'viewInsets:   ${widget.flutterInset.round()}  (flutter)',
      'composerBot:  ${widget.debouncedInset.round()}',
      composerProbeString(),
    ];
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.all(6),
        color: const Color(0xCC000000),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Color(0xFF7CFFB2),
            fontSize: 11,
            fontFamily: 'monospace',
            height: 1.35,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final line in lines) Text(line)],
          ),
        ),
      ),
    );
  }
}
