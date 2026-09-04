import 'dart:typed_data';

/// Web build: no on-device transcode exists (light_compressor_v2 is
/// Android/iOS/macOS only and ffmpeg.wasm in a PWA is not viable — 08-31
/// roadmap). Oversize videos on web keep the honest "too large" toast.
bool get isVideoTranscodeSupported => false;

Future<Uint8List?> transcodeVideoToFit(Uint8List bytes) async => null;
