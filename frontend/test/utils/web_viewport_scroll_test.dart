import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/web_viewport_scroll.dart';

void main() {
  test('resetWebDocumentScroll is a safe no-op in VM tests', () {
    expect(() => resetWebDocumentScroll(), returnsNormally);
  });
}
