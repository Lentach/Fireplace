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

    test('accepts a fragment with a c= conversation param', () {
      expect(
        isAntiQuantumNoteUrl('$baseUrl/note/$hex#abcABC012_-&c=12',
            baseUrl: baseUrl),
        isTrue,
      );
    });

    test('accepts a fragment with an e= expiry param', () {
      expect(
        isAntiQuantumNoteUrl('$baseUrl/note/$hex#abcABC012_-&e=1720000000000',
            baseUrl: baseUrl),
        isTrue,
      );
    });

    test('accepts a fragment with both c= and e= params', () {
      expect(
        isAntiQuantumNoteUrl(
            '$baseUrl/note/$hex#abcABC012_-&c=12&e=1720000000000',
            baseUrl: baseUrl),
        isTrue,
      );
    });

    test('rejects an unknown fragment param', () {
      expect(
        isAntiQuantumNoteUrl('$baseUrl/note/$hex#abc&x=1', baseUrl: baseUrl),
        isFalse,
      );
    });

    test('rejects a non-numeric c= value', () {
      expect(
        isAntiQuantumNoteUrl('$baseUrl/note/$hex#abc&c=abc', baseUrl: baseUrl),
        isFalse,
      );
    });

    test('rejects a bare trailing ampersand', () {
      expect(
        isAntiQuantumNoteUrl('$baseUrl/note/$hex#abc&', baseUrl: baseUrl),
        isFalse,
      );
    });
  });

  group('parseAntiQuantumNoteLink', () {
    test('returns null for non-note content', () {
      expect(parseAntiQuantumNoteLink('just some text', baseUrl: baseUrl),
          isNull);
      expect(
        parseAntiQuantumNoteLink('https://evil.example.org/note/$hex#abc',
            baseUrl: baseUrl),
        isNull,
      );
    });

    test('parses a note link with no expiry into a null expiresAt', () {
      final link = parseAntiQuantumNoteLink(url, baseUrl: baseUrl);
      expect(link, isNotNull);
      expect(link!.url, url);
      expect(link.expiresAt, isNull);
    });

    test('parses the e= param into expiresAt (epoch ms)', () {
      const ms = 1720000000000;
      final noteUrl = '$baseUrl/note/$hex#abcABC012_-&e=$ms';
      final link = parseAntiQuantumNoteLink(noteUrl, baseUrl: baseUrl);
      expect(link, isNotNull);
      expect(link!.url, noteUrl);
      expect(link.expiresAt, DateTime.fromMillisecondsSinceEpoch(ms));
    });

    test('ignores c= and only reads e= for expiresAt', () {
      const ms = 1720000000000;
      final noteUrl = '$baseUrl/note/$hex#abcABC012_-&c=42&e=$ms';
      final link = parseAntiQuantumNoteLink(noteUrl, baseUrl: baseUrl);
      expect(link, isNotNull);
      expect(link!.expiresAt, DateTime.fromMillisecondsSinceEpoch(ms));
    });

    test('trims surrounding whitespace before parsing', () {
      const ms = 1720000000000;
      final noteUrl = '$baseUrl/note/$hex#abcABC012_-&e=$ms';
      final link = parseAntiQuantumNoteLink('  $noteUrl \n', baseUrl: baseUrl);
      expect(link, isNotNull);
      expect(link!.url, noteUrl);
      expect(link.expiresAt, DateTime.fromMillisecondsSinceEpoch(ms));
    });
  });
}
