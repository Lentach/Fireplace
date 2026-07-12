import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/e2e_diag_log.dart';

void main() {
  test('groups repeated failures by peer and kind', () {
    final groups = E2eDiagLog.groupedFailures([
      '04:17:01 DECRYPT_DECISION | {peerId: 52, kind: duplicate}',
      '04:17:02 DECRYPT_DECISION | {peerId: 52, kind: duplicate}',
      '04:18:02 SEND_FAIL | {recipientId: 8}',
    ]);

    expect(groups, contains('peer 52 · duplicate · 2 messages'));
    expect(groups, contains('peer 8 · failure · 1 messages'));
  });

  test('since filters entries by captured timestamp', () {
    E2eDiagLog.add('RECENT', {});
    expect(E2eDiagLog.since(const Duration(hours: 24)), contains(isNotEmpty));
  });
}
