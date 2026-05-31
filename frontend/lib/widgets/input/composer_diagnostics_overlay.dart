import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../utils/web_diag_probe.dart';
import '../../utils/web_ios_webkit.dart';

/// TEMPORARY on-screen diagnostics for the iOS-WebKit composer keyboard bug
/// (composer floats mid-screen when the action panel is toggled with the
/// keyboard open). Polls the web layer at 4 Hz and prints the values that tell
/// the candidate causes apart.
///
/// To disable: flip [kComposerDiagOverlay] to `false`.
/// To remove: delete this file, `web_diag_probe*.dart`, and the usage in
/// `chat_composer_viewport.dart`.
const bool kComposerDiagOverlay = true;

class ComposerDiagnosticsOverlay extends StatefulWidget {
  const ComposerDiagnosticsOverlay({super.key, required this.debouncedInset});

  /// The viewport's debounced keyboard inset (`_keyboardInset`) — what the
  /// composer is actually `Positioned(bottom:)` at.
  final double debouncedInset;

  /// Only renders on iOS WebKit (web) while the flag is on.
  static bool get isEnabled => kComposerDiagOverlay && kIsWeb && isIOSWebKit();

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
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final probe = readWebDiagProbe();
    final lines = <String>[
      'viewInsets.bottom: ${viewInsets.round()}',
      'debouncedInset:    ${widget.debouncedInset.round()}',
      'active: ${probe['active'] ?? '-'}',
      'vv.offTop: ${probe['vv.offTop'] ?? '-'}  vv.h: ${probe['vv.h'] ?? '-'}',
      'scrollY: ${probe['win.scrollY'] ?? '-'}  doc.top: ${probe['doc.scrollTop'] ?? '-'}',
      'innerH: ${probe['win.innerH'] ?? '-'}',
    ];
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.all(6),
        color: const Color(0xB8000000),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Color(0xFF7CFFB2),
            fontSize: 10,
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
