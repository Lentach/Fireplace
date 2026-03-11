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
}
