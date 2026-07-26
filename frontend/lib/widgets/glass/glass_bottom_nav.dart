import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';
import '../icon_selection.dart';
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
/// Selection has no capsule wash and no indicator bar — an accent bar under
/// the row was drawn once and rejected ("it cover it"), and the Material
/// ripple is suppressed. What marks the active tab is the icon and label
/// cross-tinting, plus a SELECTED STATE the icon takes on.
///
/// That state is published as an [IconSelection] progress rather than applied
/// as a transform here, because one transform over three unlike shapes is
/// exactly what read as too weak. An icon that knows its own geometry
/// (`ConsoleGlyphIcon`) interpolates whatever its shape can carry — heavier
/// stroke for a closed silhouette, flooded inset regions for a cluster — and
/// a plain [Icon] ignores the value and just takes the lerped tint. This
/// widget stays icon-agnostic either way, and everything lands instantly
/// under reduce-motion.
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

  /// The entrance. Longer than the tint so the mark is still arriving as the
  /// color lands, which makes the switch read as one gesture rather than two
  /// effects. Under the playbook's 400ms cap for chrome.
  static const Duration kEntranceDuration = Duration(milliseconds: 340);

  /// The outgoing half. Deliberately quicker than the entrance so the tab you
  /// left clears while the one you chose is still arriving, rather than the
  /// two sweeps competing for attention.
  static const Duration kExitDuration = Duration(milliseconds: 200);

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
  /// How much of the ACTIVE mark is drawn over the resting one: 0 for a tab
  /// at rest, 1 for the selected tab. The muted glyph is always underneath,
  /// so both directions are a sweep across a mark that never leaves.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: GlassBottomNav.kEntranceDuration,
    reverseDuration: GlassBottomNav.kExitDuration,
    value: widget.selected ? 1 : 0,
  );

  late final CurvedAnimation _drawOn = CurvedAnimation(
    parent: _entrance,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didUpdateWidget(covariant _NavItem old) {
    super.didUpdateWidget(old);
    if (widget.reduceMotion) {
      _entrance.stop();
      _entrance.value = widget.selected ? 1 : 0;
      return;
    }
    if (widget.selected == old.selected) return;
    // Both halves of the handoff animate: the incoming tab draws its active
    // mark on, the outgoing one retracts its own. `forward`/`reverse` resume
    // from the CURRENT value rather than restarting, so hammering the tabs
    // retargets smoothly instead of snapping to an end first.
    if (widget.selected) {
      _entrance.forward();
    } else {
      _entrance.reverse();
    }
  }

  @override
  void dispose() {
    _drawOn.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.destination;
    final muted = widget.glass.onGlassMuted;
    final accent = widget.glass.onGlassAccent;
    // The icon's own color is always the ACTIVE one; how much of it you see
    // is the entrance. Lerping this toward the destination instead would make
    // the sweep invisible for its first half. The label still cross-tints.
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
          // The entrance + cross-tint ARE the tap feedback; the stock Material
          // ripple is the foreign motion this rework removes. Focus highlight
          // stays for keyboard users.
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: widget.onTap,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _drawOn,
                  builder: (context, child) => IconSelection(
                    progress: _drawOn.value,
                    activeColor: accent,
                    // Icons that cannot draw themselves partially — every
                    // plain `Icon` — just take the lerped color and fade.
                    child: IconTheme(
                      data: IconThemeData(
                        color: Color.lerp(muted, accent, _drawOn.value),
                        size: 24,
                      ),
                      child: child!,
                    ),
                  ),
                  child: (widget.selected ? d.activeIcon : null) ?? d.icon,
                ),
                const SizedBox(height: 2),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: widget.selected ? 1 : 0),
                  duration: widget.reduceMotion
                      ? Duration.zero
                      : GlassBottomNav.kTintDuration,
                  curve: Curves.easeInOut,
                  builder: (context, t, _) => Text(
                    d.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color.lerp(muted, accent, t),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
