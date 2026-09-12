// Patrol harness self-test (workflow-2.0 Batch 8.2). Framework widgets only, no app
// or backend dependency — a green run proves the runner on a target, nothing else:
//   patrol test -t integration_test/patrol_harness_test.dart -d chrome
//   patrol test -t integration_test/patrol_harness_test.dart -d emulator-5554
// Keep it this small; real coverage belongs in the *_device_test.dart files.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('patrol runner pumps, finds and taps on this target', ($) async {
    await $.pumpWidgetAndSettle(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('patrol-harness')),
          body: const _Counter(),
        ),
      ),
    );

    expect($('patrol-harness'), findsOneWidget);
    expect($('count: 0'), findsOneWidget);
    await $(Icons.add).tap();
    expect($('count: 1'), findsOneWidget);

    if (!kIsWeb) {
      await $.platform.mobile.pressHome();
    }
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _n = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('count: $_n'),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => setState(() => _n++),
          ),
        ],
      ),
    );
  }
}
