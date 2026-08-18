import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Opens the OS file picker through an invisible input POSITIONED at the
/// given viewport rect (Flutter logical px == CSS px on web).
///
/// Why not file_picker: its hidden input has no layout rect and the click is
/// not tied to a DOM interaction, so iOS Safari cannot anchor the
/// Photo Library / Take Photo or Video / Choose File popover and centers it
/// mid-screen (owner screenshot, 2026-08-17). Placing the input over the
/// paperclip tile makes Safari anchor the popover there — device-proven via
/// probe3.html (variant B anchored at the button; variant A proved DOM-event
/// anchoring, which Flutter taps cannot provide).
///
/// Resolves null on cancel (the `cancel` event is device-proven on iOS) and
/// on read failure. The input is removed on every exit path.
Future<({String name, Uint8List bytes})?> pickAttachmentFileAt({
  required double left,
  required double top,
  required double width,
  required double height,
  required String accept,
}) {
  final input =
      web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.accept = accept;
  input.style
    ..position = 'fixed'
    ..left = '${left}px'
    ..top = '${top}px'
    ..width = '${width}px'
    ..height = '${height}px'
    ..opacity = '0'
    ..zIndex = '-1'
    ..pointerEvents = 'none';
  web.document.body!.appendChild(input);

  final completer = Completer<({String name, Uint8List bytes})?>();

  void cleanup() => input.remove();

  input.addEventListener(
    'change',
    (web.Event _) {
      final file = input.files?.item(0);
      if (file == null) {
        cleanup();
        completer.complete(null);
        return;
      }
      file.arrayBuffer().toDart.then((buffer) {
        cleanup();
        completer.complete((
          name: file.name,
          bytes: buffer.toDart.asUint8List(),
        ));
      }).catchError((Object _) {
        cleanup();
        completer.complete(null);
      });
    }.toJS,
  );
  input.addEventListener(
    'cancel',
    (web.Event _) {
      cleanup();
      completer.complete(null);
    }.toJS,
  );

  input.click();
  return completer.future;
}
