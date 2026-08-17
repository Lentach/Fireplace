import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Opens the OS camera through a `capture` file input accepting BOTH
/// `image/*` and `video/*` — the broad accept list is what makes the OS
/// camera UI expose its own photo/video toggle (iOS Safari) or a
/// camera/camcorder choice (Android). image_picker cannot do this: its
/// camera source hard-locks accept to one media kind.
///
/// Desktop browsers ignore `capture` and show a file dialog — same accepted
/// degradation as the 0.1.12 camera tile. Resolves null on cancel (the
/// `cancel` event ships in every browser the PWA supports).
Future<({String name, Uint8List bytes})?> captureCameraMedia() {
  final input =
      web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.accept = 'image/*,video/*';
  input.setAttribute('capture', 'environment');
  // iOS Safari requires the input to be in the document to fire the picker.
  input.style.display = 'none';
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
