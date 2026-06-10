import 'dart:typed_data';

// Non-web: clipboard image paste arrives via other channels (Android
// contentInsertionConfiguration — Phase 4); nothing to install.
void installComposerPasteListener({
  required bool Function() shouldHandle,
  required void Function(Uint8List bytes, String mimeType, String filename)
      onImage,
  required void Function(String text) onText,
}) {}

void uninstallComposerPasteListener() {}
