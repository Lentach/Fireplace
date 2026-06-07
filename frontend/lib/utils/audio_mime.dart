/// Detects an audio container's MIME type from its leading magic bytes.
///
/// Returns `null` when the format isn't recognised (caller should then fall
/// back to a typeless blob). Used to stamp the correct `type` on a `Blob`
/// before handing its object URL to an `<audio>` element: desktop Chrome sniffs
/// a typeless blob, but **mobile Safari / mobile Chrome are strict** and fail
/// with `MEDIA_ERR_SRC_NOT_SUPPORTED` (MediaError code 4) unless the blob
/// carries a usable MIME type.
String? detectAudioMimeType(List<int> b) {
  // MP4 / M4A (AAC): bytes 4..7 == 'ftyp'.
  if (b.length >= 8 &&
      b[4] == 0x66 &&
      b[5] == 0x74 &&
      b[6] == 0x79 &&
      b[7] == 0x70) {
    return 'audio/mp4';
  }
  // WebM / Matroska (Opus): EBML header 0x1A 0x45 0xDF 0xA3.
  if (b.length >= 4 &&
      b[0] == 0x1A &&
      b[1] == 0x45 &&
      b[2] == 0xDF &&
      b[3] == 0xA3) {
    return 'audio/webm';
  }
  // WAV: 'RIFF' .... 'WAVE'.
  if (b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x41 &&
      b[10] == 0x56 &&
      b[11] == 0x45) {
    return 'audio/wav';
  }
  // OGG: 'OggS'.
  if (b.length >= 4 &&
      b[0] == 0x4F &&
      b[1] == 0x67 &&
      b[2] == 0x67 &&
      b[3] == 0x53) {
    return 'audio/ogg';
  }
  // MP3: 'ID3' tag, or an MPEG audio frame sync (0xFF Ex/Fx).
  if (b.length >= 3 && b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) {
    return 'audio/mpeg';
  }
  if (b.length >= 2 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) {
    return 'audio/mpeg';
  }
  return null;
}
