import 'dart:typed_data';

bool get canCopyImageToClipboard => false;

Future<void> copyImageToClipboard(Uint8List bytes, String mimeType) async {
  throw UnsupportedError('Image clipboard is only supported on web.');
}
