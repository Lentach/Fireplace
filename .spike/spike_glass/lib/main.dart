// Throwaway perf spike: Liquid Glass over a scrolling media-heavy chat.
// Modes: baseline | hand (BackdropFilter blur22 + saturate1.7) | pkg (liquid_glass_widgets) | fake (tint only).
// Self-driving: cycles modes, auto-scrolls, records FrameTiming, prints JSON summaries to console.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show FramePhase;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'publish_stub.dart' if (dart.library.js_interop) 'publish_web.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize();
  runApp(LiquidGlassWidgets.wrap(child: const SpikeApp()));
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SpikePage(),
      );
}

enum GlassMode { baseline, hand, hand5, pkg, fake }

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});
  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final _scroll = ScrollController();
  final _images = <ui.Image>[];
  GlassMode _mode = GlassMode.baseline;
  final _timings = <FrameTiming>[];
  bool _recording = false;
  final _results = <String, Map<String, Object>>{};

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _prepare();
  }

  void _onTimings(List<FrameTiming> t) {
    if (_recording) _timings.addAll(t);
  }

  Future<void> _prepare() async {
    // Generate 12 noisy "photo" bitmaps (raster-heavy content).
    final rnd = math.Random(7);
    for (var i = 0; i < 12; i++) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      final paint = Paint();
      for (var y = 0; y < 220; y += 4) {
        for (var x = 0; x < 320; x += 4) {
          paint.color = Color.fromARGB(
              255, rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256));
          c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 4, 4), paint);
        }
      }
      _images.add(await rec.endRecording().toImage(320, 220));
    }
    setState(() {});
    unawaited(_drive());
  }

  Future<void> _drive() async {
    await Future<void>.delayed(const Duration(seconds: 2)); // warmup/shaders
    final pinned = Uri.base.queryParameters['mode'];
    if (pinned != null) {
      setState(() => _mode = GlassMode.values.byName(pinned));
      return; // visual inspection mode, no benchmark
    }
    for (final mode in GlassMode.values) {
      setState(() => _mode = mode);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      _timings.clear();
      _recording = true;
      // 3 sweeps down/up, ~6s of continuous scrolling.
      for (var i = 0; i < 3; i++) {
        await _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 1000), curve: Curves.linear);
        await _scroll.animateTo(0,
            duration: const Duration(milliseconds: 1000), curve: Curves.linear);
      }
      _recording = false;
      _results[mode.name] = _summarize(_timings);
      // ignore: avoid_print
      print('SPIKE_RESULT ${jsonEncode({mode.name: _results[mode.name]})}');
      _publish();
    }
    // ignore: avoid_print
    print('SPIKE_DONE ${jsonEncode(_results)}');
    _done = true;
    _publish();
  }

  bool _done = false;
  String _overlay = 'running…';

  void _publish() {
    publishResult(jsonEncode({'done': _done, 'results': _results}));
    final b = StringBuffer(_done ? 'DONE\n' : 'running…\n');
    _results.forEach((k, v) {
      b.writeln(
          '$k: raster ${v['rasterAvgMs']}/${v['rasterP90Ms']}/${v['rasterP99Ms']}ms  jank ${v['jankPct']}% (${v['frames']}f)');
    });
    setState(() => _overlay = b.toString());
  }

  Map<String, Object> _summarize(List<FrameTiming> t) {
    if (t.isEmpty) return {'frames': 0};
    List<int> us(FrameTiming f, FramePhase a, FramePhase b) =>
        [f.timestampInMicroseconds(b) - f.timestampInMicroseconds(a)];
    final build = t
        .map((f) =>
            us(f, FramePhase.buildStart, FramePhase.buildFinish).first / 1000.0)
        .toList()
      ..sort();
    final raster = t
        .map((f) =>
            us(f, FramePhase.rasterStart, FramePhase.rasterFinish).first /
            1000.0)
        .toList()
      ..sort();
    double pct(List<double> v, double p) => v[(v.length * p).floor().clamp(0, v.length - 1)];
    double avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;
    final jank =
        t.where((f) => f.totalSpan.inMicroseconds > 16700).length;
    return {
      'frames': t.length,
      'buildAvgMs': double.parse(avg(build).toStringAsFixed(2)),
      'buildP90Ms': double.parse(pct(build, .90).toStringAsFixed(2)),
      'buildP99Ms': double.parse(pct(build, .99).toStringAsFixed(2)),
      'rasterAvgMs': double.parse(avg(raster).toStringAsFixed(2)),
      'rasterP90Ms': double.parse(pct(raster, .90).toStringAsFixed(2)),
      'rasterP99Ms': double.parse(pct(raster, .99).toStringAsFixed(2)),
      'framesOver16_7ms': jank,
      'jankPct': double.parse((jank * 100 / t.length).toStringAsFixed(1)),
    };
  }

  // ---- glass variants ------------------------------------------------------
  static const _saturate17 = ColorFilter.matrix(<double>[
    // saturation 1.7 matrix
    1.4487, -0.3915, -0.0572, 0, 0,
    -0.2513, 1.3085, -0.0572, 0, 0,
    -0.2513, -0.3915, 1.6428, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  Widget _navContent() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: const [
          Icon(Icons.chat_bubble, color: Color(0xFF6FB4C4)),
          Icon(Icons.people_outline, color: Color(0xFFB9C6CF)),
          Icon(Icons.settings_outlined, color: Color(0xFFB9C6CF)),
        ],
      );

  Widget _pill() {
    const radius = BorderRadius.all(Radius.circular(26));
    switch (_mode) {
      case GlassMode.baseline:
        return const SizedBox.shrink();
      case GlassMode.hand:
      case GlassMode.hand5:
        return ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ui.ImageFilter.compose(
              outer: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              inner: _saturate17,
            ),
            child: Container(
              height: 66,
              decoration: BoxDecoration(
                color: const Color(0x85202428),
                borderRadius: radius,
                border: Border.all(color: const Color(0x21BEE1EB)),
              ),
              child: _navContent(),
            ),
          ),
        );
      case GlassMode.pkg:
        return GlassContainer(
          height: 66,
          shape: const LiquidRoundedRectangle(borderRadius: 26),
          child: _navContent(),
        );
      case GlassMode.fake:
        return Container(
          height: 66,
          decoration: BoxDecoration(
            color: const Color(0xD9202428),
            borderRadius: radius,
            border: Border.all(color: const Color(0x21BEE1EB)),
            boxShadow: const [
              BoxShadow(color: Color(0x73000000), blurRadius: 28, offset: Offset(0, 8)),
            ],
          ),
          child: _navContent(),
        );
    }
  }

  Widget _glassBox({required double h, BorderRadius? radius, Widget? child}) {
    final r = radius ?? BorderRadius.circular(26);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          inner: _saturate17,
        ),
        child: Container(
          height: h,
          decoration: BoxDecoration(
            color: const Color(0x85202428),
            borderRadius: r,
            border: Border.all(color: const Color(0x21BEE1EB)),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_images.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF16171A),
      body: Stack(
        children: [
          ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 60, 12, 110),
            itemCount: 120,
            itemBuilder: (_, i) {
              final mine = i.isOdd;
              if (i % 3 == 0) {
                // media bubble
                return Align(
                  alignment:
                      mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: RawImage(
                          image: _images[i % _images.length],
                          width: 260,
                          height: 180,
                          fit: BoxFit.cover),
                    ),
                  ),
                );
              }
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 300),
                  decoration: BoxDecoration(
                    color: mine
                        ? const Color(0xFF2A4A5A)
                        : const Color(0xFF24262B),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Message $i — the quick brown fox jumps over the lazy dog, '
                    'twice, while the campfire crackles.',
                    style: const TextStyle(color: Color(0xFFF0F2F3)),
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 34,
            right: 34,
            bottom: 22,
            child: RepaintBoundary(child: _pill()),
          ),
          if (_mode == GlassMode.hand5) ...[
            Positioned(
              top: 40, left: 14, width: 52,
              child: RepaintBoundary(child: _glassBox(h: 52)),
            ),
            Positioned(
              top: 40, left: 76, right: 76,
              child: RepaintBoundary(
                  child: _glassBox(
                      h: 52,
                      child: const Center(
                          child: Text('Zosia',
                              style: TextStyle(color: Color(0xFFF0F2F3)))))),
            ),
            Positioned(
              top: 40, right: 14, width: 52,
              child: RepaintBoundary(child: _glassBox(h: 52)),
            ),
            Positioned(
              left: 12, right: 12, bottom: 100,
              child: RepaintBoundary(
                  child: _glassBox(h: 56, radius: BorderRadius.circular(28))),
            ),
          ],
          Positioned(
            top: 8,
            left: 12,
            child: Text('mode: ${_mode.name}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          Positioned(
            top: 24,
            left: 12,
            right: 12,
            child: Container(
              color: const Color(0xB3000000),
              padding: const EdgeInsets.all(6),
              child: Text(_overlay,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11, height: 1.3)),
            ),
          ),
        ],
      ),
    );
  }
}
