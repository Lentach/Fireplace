import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../utils/composer_probe.dart';
import '../../utils/web_ios_webkit.dart' show isIOSWebKit;
import '../../utils/web_keyboard_inset.dart' show lastKnownKeyboardInset;
import 'composer_keyboard_signals.dart';

/// Dev testing tool: on-screen readout of the visualViewport-derived keyboard
/// inset (what now drives the composer position) vs. Flutter's unreliable
/// `MediaQuery.viewInsets.bottom`. Off by default so real users never see it;
/// toggled at runtime by long-pressing the chat app-bar title (iOS WebKit only).
///
/// To remove entirely: delete this file and its usage in
/// `chat_composer_viewport.dart`.
final ValueNotifier<bool> composerDiagOverlayEnabled = ValueNotifier<bool>(
  false,
);

/// Flip the overlay on/off. No-op effect off iOS WebKit (overlay never mounts).
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

  /// True only where the overlay can run (iOS WebKit web). Actual visibility is
  /// further gated at runtime by [composerDiagOverlayEnabled].
  static bool get isAvailable => kIsWeb && isIOSWebKit();

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
      'predicted:    ${predictedComposerKeyboardInset.value.round()}'
          '  lastKnown: ${lastKnownKeyboardInset().round()}',
      composerProbeString(),
    ];
    return Container(
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
          children: [
            IgnorePointer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final line in lines) Text(line)],
              ),
            ),
            const SizedBox(height: 4),
            // On-device A/B toggle for the flash-fix pre-arm (H5, default
            // OFF) — the 2026-07-09 action-panel session's only live lever.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DiagToggle(label: 'FLASH', notifier: composerFlashFixEnabled),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagToggle extends StatelessWidget {
  const _DiagToggle({required this.label, required this.notifier});

  final String label;
  final ValueNotifier<bool> notifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (context, on, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => notifier.value = !on,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: on ? const Color(0xFF1E5E3A) : const Color(0xFF3A1E1E),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF7CFFB2), width: 0.5),
          ),
          child: Text(
            '$label ${on ? 'ON' : 'off'}',
            style: const TextStyle(
              color: Color(0xFF7CFFB2),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
