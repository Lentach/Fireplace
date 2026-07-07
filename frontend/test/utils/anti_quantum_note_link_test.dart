import 'package:fireplace/utils/anti_quantum_note_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baseUrl = 'https://fireplace.example.com';
  const hex = '0123456789abcdef0123456789abcdef'; // 32 lowercase hex chars
  const url = '$baseUrl/note/$hex#abcABC012_-';

  group('isAntiQuantumNoteUrl', () {
    test('accepts an exact own-origin note URL', () {
      expect(isAntiQuantumNoteUrl(url, baseUrl: baseUrl), isTrue);
    });

    test('accepts a fragment key with = padding', () {
      expect(
        isAntiQuantumNoteUrl('$baseUrl/note/$hex#abc=', baseUrl: baseUrl),
        isTrue,
      );
      expect(
        isAntiQuantumNoteUrl('$baseUrl/note/$hex#abc==', baseUrl: baseUrl),
        isTrue,
      );
    });

    test('accepts a URL with surrounding whitespace (trimmed)', () {
      expect(
        isAntiQuantumNoteUrl('  \n\t$url  \n', baseUrl: baseUrl),
        isTrue,
      );
    });

    test('rejects a URL embedded in prose', () {
      expect(
        isAntiQuantumNoteUrl('check this $url out', baseUrl: baseUrl),
        isFalse,
      );
    });

    test('rejects a foreign host', () {
      expect(
        isAntiQuantumNoteUrl(
          'https://evil.example.org/note/$hex#abc',
          baseUrl: baseUrl,
        ),
        isFalse,
      );
    });

    test('rejects a note URL missing the key fragment', () {
      expect(
        isAntiQuantumNoteUrl('$baseUrl/note/$hex', baseUrl: baseUrl),
        isFalse,
      );
      expect(
        isAntiQuantumNoteUrl('$baseUrl/note/$hex#', baseUrl: baseUrl),
        isFalse,
      );
    });

    test('rejects a token of the wrong length (31 or 33 hex chars)', () {
      const hex31 = '0123456789abcdef0123456789abcde'; // 31 chars
      const hex33 = '0123456789abcdef0123456789abcdef0'; // 33 chars
      expect(
        isAntiQuantumNoteUrl('$baseUrl/note/$hex31#abc', baseUrl: baseUrl),
        isFalse,
      );
      expect(
        isAntiQuantumNoteUrl('$baseUrl/note/$hex33#abc', baseUrl: baseUrl),
        isFalse,
      );
    });

    test('rejects an uppercase-hex token', () {
      const upper = '0123456789ABCDEF0123456789ABCDEF';
      expect(
        isAntiQuantumNoteUrl('$baseUrl/note/$upper#abc', baseUrl: baseUrl),
        isFalse,
      );
    });

    test('rejects trailing characters after the fragment', () {
      expect(
        isAntiQuantumNoteUrl('$url trailing', baseUrl: baseUrl),
        isFalse,
      );
      expect(
        isAntiQuantumNoteUrl('$url/more', baseUrl: baseUrl),
        isFalse,
      );
    });
  });
}
