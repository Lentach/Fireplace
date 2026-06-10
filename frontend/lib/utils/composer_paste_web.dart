import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool _installed = false;
JSFunction? _listener;
bool Function()? _shouldHandle;
void Function(Uint8List bytes, String mimeType, String filename)? _onImage;
void Function(String text)? _onText;

void installComposerPasteListener({
  required bool Function() shouldHandle,
  required void Function(Uint8List bytes, String mimeType, String filename)
      onImage,
  required void Function(String text) onText,
}) {
  _shouldHandle = shouldHandle;
  _onImage = onImage;
  _onText = onText;
  if (_installed) return;
  _installed = true;
  _listener = _onPasteCapture.toJS;
  // passive: false is required so preventDefault() is allowed.
  web.window.addEventListener(
    'paste',
    _listener,
    web.AddEventListenerOptions(capture: true, passive: false),
  );
}

void uninstallComposerPasteListener() {
  _shouldHandle = null;
  _onImage = null;
  _onText = null;
  if (!_installed) return;
  _installed = false;
  web.window.removeEventListener('paste', _listener, true.toJS);
  _listener = null;
}

void _onPasteCapture(web.Event event) {
  if (!event.isA<web.ClipboardEvent>()) return;
  if (!(_shouldHandle?.call() ?? false)) return;
  final data = (event as web.ClipboardEvent).clipboardData;
  if (data == null) return;

  // First image in clipboardData.files (Chromium/Firefox paste-image path —
  // spec §2; navigator.clipboard.read() is permission-gated and avoided),
  // falling back to .items (historically the Safari/WebKit path).
  final imageFile =
      _firstImageFromFiles(data.files) ?? _firstImageFromItems(data.items);
  if (imageFile == null) return; // text-only paste: let the browser handle it

  // We own this paste: stop the native insertion, forward text + image.
  event.preventDefault();
  final text = data.getData('text/plain');
  if (text.isNotEmpty) _onText?.call(text);

  final file = imageFile;
  final mime = file.type;
  final name = file.name.isNotEmpty ? file.name : _defaultName(mime);
  file.arrayBuffer().toDart.then((JSArrayBuffer buf) {
    _onImage?.call(buf.toDart.asUint8List(), mime, name);
  });
}

web.File? _firstImageFromFiles(web.FileList files) {
  for (var i = 0; i < files.length; i++) {
    final f = files.item(i);
    if (f != null && f.type.startsWith('image/')) return f;
  }
  return null;
}

web.File? _firstImageFromItems(web.DataTransferItemList items) {
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item.kind == 'file' && item.type.startsWith('image/')) {
      final f = item.getAsFile();
      if (f != null) return f;
    }
  }
  return null;
}

String _defaultName(String mime) {
  final ext = switch (mime) {
    'image/png' => 'png',
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    _ => 'img',
  };
  return 'pasted.$ext';
}
