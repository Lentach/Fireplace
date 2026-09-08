import 'package:fireplace/services/device_link/link_code_extract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const v1Code =
      'fp-link.v1.123e4567-e89b-42d3-a456-426614174000.BWtleWJ5dGVz.web';
  const v2Code =
      'fp-link.v2.123e4567-e89b-42d3-a456-426614174000.BWtleWJ5dGVz.android.p';

  group('extractLinkCode', () {
    test('returns a bare v1 code unchanged', () {
      expect(extractLinkCode(v1Code), v1Code);
    });

    test('returns a bare v2 code unchanged (role segment intact)', () {
      expect(extractLinkCode(v2Code), v2Code);
    });

    test('trims surrounding whitespace from a scanned code', () {
      expect(extractLinkCode('  $v2Code\n'), v2Code);
    });

    test('extracts the code from a deep-link URL fragment', () {
      expect(
        extractLinkCode('https://fireplace.ignorelist.com/link#$v2Code'),
        v2Code,
      );
    });

    test('extracts from any origin — the host only opened the app', () {
      expect(extractLinkCode('http://localhost:8080/link#$v1Code'), v1Code);
    });

    test('rejects a URL without a link fragment', () {
      expect(extractLinkCode('https://fireplace.ignorelist.com/link'), isNull);
      expect(
        extractLinkCode('https://fireplace.ignorelist.com/link#other'),
        isNull,
      );
    });

    test('rejects unknown code versions', () {
      expect(extractLinkCode('fp-link.v3.abc.def.web'), isNull);
      expect(extractLinkCode('fp-link.v1'), isNull);
    });

    test('rejects arbitrary text', () {
      expect(extractLinkCode('hello world'), isNull);
      expect(extractLinkCode(''), isNull);
    });
  });
}
