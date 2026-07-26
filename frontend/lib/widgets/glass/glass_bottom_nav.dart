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
/// Selection is CROSS-TINT ONLY (owner call, 2026-07-26): icon and label
/// tween between the muted and accent on-glass colors, so the active tab
/// changes by color alone. There is deliberately no capsule wash and no
/// underline/indicator bar — an accent bar under the row was drawn once and
/// rejected ("it cover it"), and the stock Material ripple is suppressed.
/// The tint tween lands instantly under reduce-motion.
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
  static const Duration kTintDuration = Duration(milliseconds: 200);

  /// The selection pulse. Slightly longer than the tint so the glyph is still
  /// settling as the color lands, which is what makes the switch read as one
  /// gesture rather than two effects.
  static const Duration kPulseDuration = Duration(milliseconds: 240);

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 8, 34, 12),
      child: GlassPill(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: _NavItem(
                  destination: destinations[i],
                  selected: i == currentIndex,
                  reduceMotion: reduceMotion,
                  glass: glass,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One destination cell.
///
/// Stateful because the selection PULSE is a one-shot that has to fire on the
/// transition into selected — a plain implicit tween would only animate the
/// steady state and could not replay when you return to a tab.
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.reduceMotion,
    required this.glass,
    required this.onTap,
  });

  final GlassNavDestination destination;
  final bool selected;
  final bool reduceMotion;
  final GlassTheme glass;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: GlassBottomNav.kPulseDuration,
  );

  /// Dip, overshoot, settle: 1.0 → 0.92 → 1.06 → 1.0. Written as explicit
  /// keyframes so the shape is the code rather than a comment about it, and
  /// so it lands on exactly 1.0 with no trailing spring.
  late final Animation<double> _pulseScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.92,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.92,
        end: 1.06,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.06,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 30,
    ),
  ]).animate(_pulse);

  @override
  void didUpdateWidget(covariant _NavItem old) {
    super.didUpdateWidget(old);
    if (widget.reduceMotion) {
      _pulse.stop();
      _pulse.value = 0;
      return;
    }
    // Fire only on the transition INTO selected, restarting from zero so
    // hammering the tabs retargets instead of queueing pulses.
    if (widget.selected && !old.selected) {
      _pulse.forward(from: 0);
    } else if (!widget.selected && old.selected) {
      // Leaving mid-pulse must not keep a muted glyph animating.
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.destination;
    // One authoritative semantics node per destination: label + button +
    // selected + tap, with the visual subtree excluded so the Text/icon do
    // not produce duplicate nodes.
    return Semantics(
      label: d.label,
      button: true,
      selected: widget.selected,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          // The pulse + cross-tint ARE the tap feedback; the stock Material
          // ripple is the foreign motion this rework removes. Focus highlight
          // stays for keyboard users.
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: widget.onTap,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: widget.selected ? 1 : 0),
            duration: widget.reduceMotion
                ? Duration.zero
                : GlassBottomNav.kTintDuration,
            curve: Curves.easeInOut,
            builder: (context, t, _) {
              final color = Color.lerp(
                widget.glass.onGlassMuted,
                widget.glass.onGlassAccent,
                t,
              )!;
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseScale,
                      // The glyph subtree is rebuilt by the tint tween above;
                      // the pulse only needs to re-apply a transform, so it
                      // rides the `child` slot and does not rebuild it again.
                      builder: (context, child) => Transform.scale(
                        scale: _pulseScale.value,
                        child: child,
                      ),
                      child: IconTheme(
                        data: IconThemeData(color: color, size: 24),
                        child:
                            (widget.selected ? d.activeIcon : null) ?? d.icon,
                      ),
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
