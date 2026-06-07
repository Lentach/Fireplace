import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/page_load_nonce.dart';
import 'package:fireplace/utils/mic_permission_state_stub.dart' as mic;

void main() {
  test('page-load nonce is non-empty and stable within the process', () {
    expect(kPageLoadNonce, isNotEmpty);
    expect(kPageLoadNonce, equals(kPageLoadNonce));
  });

  test('mic permission stub reports unsupported off-web', () async {
    expect(await mic.queryMicPermissionState(), 'unsupported');
  });
}
