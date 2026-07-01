import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/page_load_nonce.dart';

void main() {
  test('page-load nonce is non-empty and stable within the process', () {
    expect(kPageLoadNonce, isNotEmpty);
    expect(kPageLoadNonce, equals(kPageLoadNonce));
  });
}
