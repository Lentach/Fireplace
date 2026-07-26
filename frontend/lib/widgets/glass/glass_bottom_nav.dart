import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';
import 'glass_surface.dart';

/// One destination of [GlassBottomNav].
class GlassNavDestination {
  final Widget icon;

  /// Icon when selected; falls back to [icon].
  final Widget? activeIcon;
  final String label;

  const GlassNavDestination({
    required this.icon,
    this.activeIcon,
    required this.label,
  });
}

/// Floating pill bottom navigation (accepted spec §5): 66px glass pill inset
/// 34px sides / 12px bottom.
///
/// Selection is TRACE-LIT (owner direction B, 2026-07-26), not a capsule
/// wash: one accent trace segment lives under the icon row and travels to the
/// selected tab on change — a miniature of the honeycomb's route fill: the
/// signal moves to the node you selected. Icon and label cross-tint on a real
/// color tween rather than swapping. Both land instantly under reduce-motion.
class GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassNavDestination> destinations;

  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.destinations,
  });

  /// State-change motion per the playbook: 200ms easeInOut, zero under
  /// reduce-motion.
  static const Duration _kMotion = Duration(milliseconds: 200);
  static const double _kTraceWidth = 28;
  static const double _kTraceThickness = 2.5;

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _kMotion;
    final n = destinations.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 8, 34, 12),
      child: GlassPill(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Stack(
          children: [
            // The lit trace. AnimatedAlign slides it between slot centres:
            // with a 1/n-wide slot box, x = -1 + 2i/(n-1) lands each stop on
            // the i-th slot's centre.
            AnimatedAlign(
              alignment: Alignment(
                n <= 1 ? 0 : -1 + 2 * currentIndex / (n - 1),
                1,
              ),
              duration: duration,
              curve: Curves.easeInOut,
              child: FractionallySizedBox(
                widthFactor: n == 0 ? 1 : 1 / n,
                child: Center(
                  child: Container(
                    width: _kTraceWidth,
                    height: _kTraceThickness,
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: glass.onGlassAccent,
                      borderRadius: BorderRadius.circular(_kTraceThickness / 2),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(child: _item(context, glass, duration, i)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    GlassTheme glass,
    Duration duration,
    int index,
  ) {
    final d = destinations[index];
    final selected = index == currentIndex;
    // One authoritative semantics node per destination: label + button +
    // selected + tap, with the visual subtree excluded so the Text/icon do
    // not produce duplicate nodes.
    return Semantics(
      label: d.label,
      button: true,
      selected: selected,
      onTap: () => onTap(index),
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          // The traveling trace + cross-tint ARE the tap feedback; the stock
          // Material ripple is the foreign motion this rework removes. Focus
          // highlight stays for keyboard users.
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: () => onTap(index),
          // Cross-tint instead of swap: the tween retargets whenever the
          // selection flips, so outgoing fades accent→muted while incoming
          // fades muted→accent.
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: selected ? 1 : 0),
            duration: duration,
            curve: Curves.easeInOut,
            builder: (context, t, _) {
              final color = Color.lerp(
                glass.onGlassMuted,
                glass.onGlassAccent,
                t,
              )!;
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconTheme(
                      data: IconThemeData(color: color, size: 24),
                      child: (selected ? d.activeIcon : null) ?? d.icon,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
