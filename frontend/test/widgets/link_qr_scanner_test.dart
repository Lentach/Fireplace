import 'package:fireplace/widgets/link_qr_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// The VM test host resolves the facade to the NATIVE impl (dart.library.io),
// where the host is neither Android nor iOS — i.e. the unsupported path,
// exactly what a desktop native build would hit. Falsification for the
// unsupported contract: an impl that mounted MobileScanner regardless, or
// never fired onUnsupported, fails the assertions below.
void main() {
  testWidgets('unsupported host renders nothing and reports it once', (
    tester,
  ) async {
    final codes = <String>[];
    var unsupportedCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LinkQrScanner(
          onCode: codes.add,
          onUnsupported: () => unsupportedCalls++,
        ),
      ),
    );
    // The widget mounts without throwing…
    expect(find.byType(LinkQrScanner), findsOneWidget);
    // …and after the first frame the unsupported callback has fired ONCE.
    await tester.pump();
    expect(unsupportedCalls, 1);
    expect(codes, isEmpty);
    // No camera pipeline was mounted.
    expect(find.byType(MobileScanner), findsNothing);
    // A rebuild does not re-report.
    await tester.pump();
    expect(unsupportedCalls, 1);
  });

  testWidgets('onUnsupported is optional', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: LinkQrScanner(onCode: (_) {})),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('linkQrScanSupported answers false off Android/iOS', () async {
    expect(await linkQrScanSupported(), isFalse);
  });
}
