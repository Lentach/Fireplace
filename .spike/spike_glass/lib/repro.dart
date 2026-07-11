// Minimal correct-API repro: one bounded GlassContainer pill over a labeled
// grid, initialized per package docs. If the whole grid blurs, the defect is
// in the package's web path, not our harness composition.
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize();
  runApp(LiquidGlassWidgets.wrap(child: const ReproApp()));
}

class ReproApp extends StatelessWidget {
  const ReproApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF16171A),
        body: Stack(
          children: [
            // Labeled grid background — must stay SHARP outside the pill.
            GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4),
              itemCount: 80,
              itemBuilder: (_, i) => Container(
                margin: const EdgeInsets.all(4),
                color: Colors.primaries[i % Colors.primaries.length].shade700,
                alignment: Alignment.center,
                child: Text('$i',
                    style: const TextStyle(color: Colors.white, fontSize: 22)),
              ),
            ),
            Center(
              child: GlassContainer(
                width: 240,
                height: 66,
                shape: const LiquidRoundedRectangle(borderRadius: 26),
                child: const Center(
                  child: Text('glass pill',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
