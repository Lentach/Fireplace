// Cosmic starfield performance spike. Drives the PRODUCTION path:
// RpgTheme.themeDataCosmic -> ChatBackgroundPattern -> StarfieldBackground,
// behind a real scrolling ListView of chat bubbles. Prints aggregated frame
// timings every 4s. Density is overridden through the real CosmicBackdrop
// theme extension, so the measured compositing/layering matches production.
//
// Run (web):    flutter run -d web-server --web-port 8099 -t tool/starfield_spike.dart --profile
// Run (mobile): flutter run -d <android> -t tool/starfield_spike.dart --profile
// Tap the screen to cycle density: 240 (site baseline) -> 120 -> 60 -> 0 (opaque, no field).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:fireplace/theme/cosmic_theme.dart';
import 'package:fireplace/theme/glass_theme.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/chat_background_pattern.dart';

void main() => runApp(const _SpikeApp());

class _SpikeApp extends StatelessWidget {
  const _SpikeApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RpgTheme.themeDataCosmic,
        home: const _SpikePage(),
      );
}

class _SpikePage extends StatefulWidget {
  const _SpikePage();
  @override
  State<_SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<_SpikePage> {
  final _scroll = ScrollController();
  final List<FrameTiming> _buf = [];
  final List<int> _densities = [240, 120, 60, 0];
  int _densityIdx = 0;
  Timer? _report;
  Timer? _scrollTick;
  bool _down = true;
  String _stats = 'measuring…';

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _scrollTick = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      var next = _scroll.offset + (_down ? 24 : -24);
      if (next >= max) {
        next = max;
        _down = false;
      } else if (next <= 0) {
        next = 0;
        _down = true;
      }
      _scroll.jumpTo(next);
    });
    _report = Timer.periodic(const Duration(seconds: 4), (_) => _flush());
  }

  void _onTimings(List<FrameTiming> t) => _buf.addAll(t);

  double _pct(List<double> xs, double p) {
    if (xs.isEmpty) return 0;
    xs.sort();
    return xs[((xs.length - 1) * p).round()];
  }

  void _flush() {
    if (_buf.isEmpty) return;
    final build =
        _buf.map((t) => t.buildDuration.inMicroseconds / 1000.0).toList();
    final raster =
        _buf.map((t) => t.rasterDuration.inMicroseconds / 1000.0).toList();
    final total =
        _buf.map((t) => t.totalSpan.inMicroseconds / 1000.0).toList();
    final jank16 = total.where((ms) => ms > 16.7).length;
    final n = _buf.length;
    // ignore: avoid_print
    print(
      'SPIKE density=${_densities[_densityIdx]} frames=$n '
      'build[p50=${_pct(build, .5).toStringAsFixed(2)} '
      'p95=${_pct(build, .95).toStringAsFixed(2)} '
      'max=${build.reduce((a, b) => a > b ? a : b).toStringAsFixed(2)}] '
      'raster[p50=${_pct(raster, .5).toStringAsFixed(2)} '
      'p95=${_pct(raster, .95).toStringAsFixed(2)} '
      'max=${raster.reduce((a, b) => a > b ? a : b).toStringAsFixed(2)}] '
      'jank>16.7=$jank16/${total.length} '
      '(${(100 * jank16 / total.length).toStringAsFixed(1)}%)',
    );
    if (mounted) {
      setState(() => _stats = 'd=${_densities[_densityIdx]} '
          'build p50/${_pct(build, .5).toStringAsFixed(1)} '
          'p95/${_pct(build, .95).toStringAsFixed(1)} '
          'max/${build.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}  '
          'rast p50/${_pct(raster, .5).toStringAsFixed(1)} '
          'p95/${_pct(raster, .95).toStringAsFixed(1)}  '
          'jank ${(100 * jank16 / total.length).toStringAsFixed(1)}%');
    }
    _buf.clear();
  }

  void _cycle() {
    setState(() => _densityIdx = (_densityIdx + 1) % _densities.length);
    _buf.clear();
    // ignore: avoid_print
    print('SPIKE -> density now ${_densities[_densityIdx]}');
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _report?.cancel();
    _scrollTick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final fc = base.extension<FireplaceColors>()!;
    final density = _densities[_densityIdx];
    // Override density through the REAL CosmicBackdrop extension so
    // ChatBackgroundPattern renders the exact production starfield path.
    final themed = base.copyWith(
      extensions: [
        fc,
        base.extension<GlassTheme>()!,
        CosmicBackdrop.starfield.copyWith(density: density),
      ],
    );
    final list = ListView.builder(
      controller: _scroll,
      itemCount: 200,
      itemBuilder: (context, i) {
        final mine = i.isEven;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(maxWidth: 260),
            decoration: BoxDecoration(
              color: mine ? fc.mineMsgBg : fc.theirsMsgBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Message $i — the quick brown fox jumps over the lazy dog',
              style: TextStyle(
                color: mine ? Colors.white : const Color(0xFFCFE2F2),
              ),
            ),
          ),
        );
      },
    );
    return Scaffold(
      body: Stack(
        children: [
          GestureDetector(
            onTap: _cycle,
            // density 0 -> enabled:false -> opaque space base (real fallback).
            child: Theme(
              data: themed,
              child: ChatBackgroundPattern(
                backgroundColor: RpgTheme.messagesAreaBgCosmic,
                enabled: density > 0,
                child: list,
              ),
            ),
          ),
          Positioned(
            top: 40,
            left: 8,
            right: 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black.withValues(alpha: 0.72),
                child: Text(
                  _stats,
                style: const TextStyle(
                  color: Color(0xFF9EFF9E),
                  fontSize: 12,
                ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
