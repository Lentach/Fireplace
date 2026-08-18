import 'dart:typed_data';

/// Off-web stub — non-web platforms use FilePicker in the caller instead.
Future<({String name, Uint8List bytes})?> pickAttachmentFileAt({
  required double left,
  required double top,
  required double width,
  required double height,
  required String accept,
}) async => null;
