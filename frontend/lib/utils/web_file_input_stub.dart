import 'dart:ui' show Rect;

import 'web_file_input.dart' show WebPickedFile;

bool get webAnchoredFileInputSupported => false;

Future<WebPickedFile?> pickFileViaAnchoredInput({
  required Rect anchorRect,
  required String accept,
  String? capture,
}) async => null;
