import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/link_preview_service.dart';

void main() {
  group('LinkPreviewService.isSafeImageUrl', () {
    test('returns false for null or empty', () {
      expect(LinkPreviewService.isSafeImageUrl(null), false);
      expect(LinkPreviewService.isSafeImageUrl(''), false);
    });

    test('returns true for valid HTTPS public URL', () {
      expect(
        LinkPreviewService.isSafeImageUrl('https://example.com/image.png'),
        true,
      );
      expect(
        LinkPreviewService.isSafeImageUrl('https://cdn.example.org/img.jpg'),
        true,
      );
    });

    test('returns false for HTTP (non-HTTPS)', () {
      expect(
        LinkPreviewService.isSafeImageUrl('http://example.com/image.png'),
        false,
      );
    });

    test('returns false for localhost', () {
      expect(
        LinkPreviewService.isSafeImageUrl('https://localhost/image.png'),
        false,
      );
      expect(
        LinkPreviewService.isSafeImageUrl('https://127.0.0.1/image.png'),
        false,
      );
    });

    test('returns false for private IP ranges', () {
      expect(
        LinkPreviewService.isSafeImageUrl('https://10.0.0.1/image.png'),
        false,
      );
      expect(
        LinkPreviewService.isSafeImageUrl('https://192.168.1.1/image.png'),
        false,
      );
      expect(
        LinkPreviewService.isSafeImageUrl('https://172.16.0.1/image.png'),
        false,
      );
    });

    test('returns false for IPv6 loopback and ULA hosts', () {
      // Bracketed IPv6 hosts are normalised (brackets stripped) before the
      // private-range check. ::1 is loopback; fd00::/8 is a ULA (fc00::/7).
      expect(
        LinkPreviewService.isSafeImageUrl('https://[::1]/x.png'),
        false,
      );
      expect(
        LinkPreviewService.isSafeImageUrl('https://[fd00::1]/x.png'),
        false,
      );
    });

    test('over-broad `fd` prefix also rejects a legitimate public host', () {
      // KNOWN LIMITATION: the ULA alternative `fd` in the private-IP regex is
      // not anchored to an IPv6 boundary, so it swallows any hostname starting
      // with "fd" — including this legitimate public CDN. The intended result
      // is `true`; fixing it needs a source-side regex boundary (out of scope
      // for a test-only change). This case pins the current behaviour so the
      // over-broad match is documented and any future fix must update it.
      expect(
        LinkPreviewService.isSafeImageUrl('https://fdcdn.example.com/x.png'),
        false,
      );
    });

    test('resolves relative URL against pageUrl', () {
      expect(
        LinkPreviewService.isSafeImageUrl(
          '/images/thumb.png',
          'https://example.com/article',
        ),
        true,
      );
    });

    test('returns false when relative URL resolves to private host', () {
      expect(
        LinkPreviewService.isSafeImageUrl(
          '/images/thumb.png',
          'https://192.168.1.1/article',
        ),
        false,
      );
    });

    test('returns false for invalid URL', () {
      expect(LinkPreviewService.isSafeImageUrl('not-a-url'), false);
      expect(LinkPreviewService.isSafeImageUrl('://missing-scheme'), false);
    });
  });

  group('LinkPreviewService.extractFirstUrl', () {
    test('returns null for text without a URL', () {
      expect(LinkPreviewService.extractFirstUrl(''), isNull);
      expect(LinkPreviewService.extractFirstUrl('just some plain text'), isNull);
      expect(LinkPreviewService.extractFirstUrl('email me at a@b.com'), isNull);
    });

    test('finds the URL embedded in surrounding text', () {
      expect(
        LinkPreviewService.extractFirstUrl('check this https://example.com out'),
        'https://example.com',
      );
    });

    test('preserves the #fragment (note decryption key) in the result', () {
      const noteUrl = 'https://host/note/abc123#SGVsbG8=';
      expect(
        LinkPreviewService.extractFirstUrl('open $noteUrl now'),
        noteUrl,
      );
      // The key material must survive extraction so the display path can decrypt.
      expect(LinkPreviewService.extractFirstUrl(noteUrl), contains('#SGVsbG8='));
    });

    test('returns the FIRST of multiple URLs', () {
      expect(
        LinkPreviewService.extractFirstUrl(
          'first https://a.example second https://b.example',
        ),
        'https://a.example',
      );
    });
  });

  group('LinkPreviewService.stripFragment', () {
    test('removes the #key from a note-style URL', () {
      expect(
        LinkPreviewService.stripFragment('https://host/note/abc123#SGVsbG8='),
        'https://host/note/abc123',
      );
    });

    test('is a no-op for a fragment-less URL', () {
      const url = 'https://host/note/abc123';
      expect(LinkPreviewService.stripFragment(url), url);
    });

    test('cuts at the FIRST # when several are present', () {
      expect(
        LinkPreviewService.stripFragment('https://host/page#a#b#c'),
        'https://host/page',
      );
    });

    test('stripped note URL never leaks the key material', () {
      const key = 'SGVsbG8gc2VjcmV0IGtleQ==';
      final stripped =
          LinkPreviewService.stripFragment('https://host/note/xyz#$key');
      expect(stripped, isNot(contains(key)));
      expect(stripped, isNot(contains('#')));
    });
  });
}
