import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/audio_mime.dart';

void main() {
  group('detectAudioMimeType', () {
    test('MP4/M4A (ftyp iso5) — the exact bytes from the failing prod log', () {
      // [0,0,0,32,'f','t','y','p','i','s','o','5'] = 0,0,0,32,102,116,121,112,105,115,111,53
      final bytes = [0, 0, 0, 32, 102, 116, 121, 112, 105, 115, 111, 53];
      expect(detectAudioMimeType(bytes), 'audio/mp4');
    });

    test('MP4 with a different brand (ftyp M4A )', () {
      final bytes = [0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20];
      expect(detectAudioMimeType(bytes), 'audio/mp4');
    });

    test('WebM / Matroska (EBML header) → audio/webm', () {
      final bytes = [0x1A, 0x45, 0xDF, 0xA3, 0x01, 0x00, 0x00, 0x00];
      expect(detectAudioMimeType(bytes), 'audio/webm');
    });

    test('WAV (RIFF…WAVE) → audio/wav', () {
      final bytes = [
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x24, 0x08, 0x00, 0x00, // size
        0x57, 0x41, 0x56, 0x45, // WAVE
      ];
      expect(detectAudioMimeType(bytes), 'audio/wav');
    });

    test('OGG (OggS) → audio/ogg', () {
      final bytes = [0x4F, 0x67, 0x67, 0x53, 0x00, 0x02, 0x00, 0x00];
      expect(detectAudioMimeType(bytes), 'audio/ogg');
    });

    test('MP3 (ID3 tag) → audio/mpeg', () {
      final bytes = [0x49, 0x44, 0x33, 0x04, 0x00, 0x00];
      expect(detectAudioMimeType(bytes), 'audio/mpeg');
    });

    test('MP3 (frame sync) → audio/mpeg', () {
      final bytes = [0xFF, 0xFB, 0x90, 0x00];
      expect(detectAudioMimeType(bytes), 'audio/mpeg');
    });

    test('unknown / too short → null (caller falls back to typeless blob)', () {
      expect(detectAudioMimeType([1, 2, 3]), isNull);
      expect(detectAudioMimeType([]), isNull);
      expect(detectAudioMimeType([0x00, 0x01, 0x02, 0x03, 0x04, 0x05]), isNull);
    });
  });
}
