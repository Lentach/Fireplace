import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/page_load_nonce.dart';

void main() {
  test('page-load nonce is non-empty and stable within the process', () {
    expect(kPageLoadNonce, isNotEmpty);
    // Defends the documented two-part radix-36 shape (<base36>-<base36>);
    // catches a regression dropping the separator or a segment.
    expect(kPageLoadNonce, matches(RegExp(r'^[0-9a-z]+-[0-9a-z]+$')));
  });
}
