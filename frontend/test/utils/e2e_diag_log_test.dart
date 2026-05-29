import 'package:fireplace/utils/e2e_diag_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => E2eDiagLog.clear());

  group('E2eDiagLog', () {
    test('add() appends an entry', () {
      E2eDiagLog.add('STEP_A', {'key': 'val'});
      expect(E2eDiagLog.entries.length, 1);
      expect(E2eDiagLog.entries.first, contains('STEP_A'));
    });

    test('cap enforcement: 201st entry drops the oldest', () {
      for (var i = 0; i < 201; i++) {
        E2eDiagLog.add('STEP_$i', {});
      }
      expect(E2eDiagLog.entries.length, 200);
      expect(E2eDiagLog.entries.first, contains('STEP_1'));
      expect(E2eDiagLog.entries.last, contains('STEP_200'));
    });

    test('clear() empties the list', () {
      E2eDiagLog.add('STEP_A', {});
      E2eDiagLog.add('STEP_B', {});
      E2eDiagLog.clear();
      expect(E2eDiagLog.entries, isEmpty);
    });

    test('entries is an immutable snapshot — mutation after read does not affect it', () {
      E2eDiagLog.add('STEP_A', {});
      final snapshot = E2eDiagLog.entries;
      final lengthBeforeAdd = snapshot.length;
      E2eDiagLog.add('STEP_B', {});
      expect(lengthBeforeAdd, 1);
      expect(snapshot.length, 1);           // snapshot not affected by subsequent add
      expect(E2eDiagLog.entries.length, 2); // live list has 2
    });

    test('entries list is unmodifiable — throws on mutation attempt', () {
      E2eDiagLog.add('STEP_A', {});
      expect(() => E2eDiagLog.entries.add('x'), throwsUnsupportedError);
    });

    test('entry format contains timestamp, step, and data', () {
      E2eDiagLog.add('DECRYPT_OK', {'msgId': 42});
      final entry = E2eDiagLog.entries.first;
      expect(entry, matches(RegExp(r'\d{2}:\d{2}:\d{2}')));
      expect(entry, contains('DECRYPT_OK'));
      expect(entry, contains('msgId'));
    });
  });
}
