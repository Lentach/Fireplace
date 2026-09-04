import 'package:fireplace/services/passcode_unlock_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PasscodeUnlockGate gate;

  setUp(() => gate = PasscodeUnlockGate());

  test('open by default — a device without a passcode never waits', () async {
    // The whole E2E boot sits behind this. A valve that defaulted to closed
    // would stall the encryption stack for every user who has no passcode.
    expect(gate.isOpen, isTrue);
    await gate.waitUntilOpen(); // completes, does not hang
  });

  test('a closed gate releases every waiter when it opens', () async {
    gate.close();
    var released = 0;
    final waits = [
      gate.waitUntilOpen().then((_) => released++),
      gate.waitUntilOpen().then((_) => released++),
    ];

    await Future<void>.delayed(Duration.zero);
    expect(released, 0);

    gate.open();
    await Future.wait(waits);
    expect(released, 2);
  });

  test('opening twice is harmless, and reopening after a re-close works',
      () async {
    gate.close();
    gate.open();
    gate.open();
    await gate.waitUntilOpen();

    gate.close();
    final wait = gate.waitUntilOpen();
    gate.open();
    await wait;

    expect(gate.isOpen, isTrue);
  });
}
