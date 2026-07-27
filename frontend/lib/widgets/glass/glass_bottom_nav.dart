import 'dart:math' as math;

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
///
/// The handoff itself is one gesture in two beats. The lens stretches out of
/// its slot and glides to the one you chose; only once it is most of the way
/// there does that tab light up. It DELIVERS the selection rather than racing
/// it — the travel and the entrance used to start on the same frame and read
/// as two unrelated effects firing at once.
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

  /// Height of the pill itself. The lens is sized and centred against this.
  static const double kPillHeight = 66;

  /// The entrance, measured from the tap to a fully drawn active mark. It sits
  /// exactly on the playbook's 400ms ceiling for chrome because it is not
  /// 400ms of animation: [kDrawOnStart] of it is a deliberate wait, and the
  /// draw itself is 240ms, inside the playbook's 180–280ms band.
  static const Duration kEntranceDuration = Duration(milliseconds: 400);

  /// Where in the entrance the destination starts lighting up. 0.4 of 400ms is
  /// a 160ms wait, by which point the lens is 59% of the way across
  /// (`easeInOutCubic(160/300)`).
  ///
  /// This is also the dial for the one risk in the idea: 160ms of stillness on
  /// the tab you just touched. Lower it if the tap feels unacknowledged on
  /// device.
  static const double kDrawOnStart = 0.4;

  /// The outgoing half. Deliberately quicker than the entrance and NOT delayed
  /// — the tab you left clears immediately, which is what keeps the tap
  /// acknowledged while the incoming one is still waiting on the lens.
  static const Duration kExitDuration = Duration(milliseconds: 200);

  /// The lens's travel between slots. `easeInOutCubic` because this is a
  /// journey with two ends, not an arrival.
  static const Duration kTravelDuration = Duration(milliseconds: 300);

  /// Height of the pool of glass under the active tab, at rest.
  static const double kLensHeight = 50;

  /// How much wider the lens gets at the midpoint of a ONE-slot hop, as a
  /// fraction of a slot. Scales with the distance travelled, so a two-slot
  /// jump elongates twice as far and reads as the longer throw it is.
  static const double kLensStretch = 0.4;

  /// How much shorter it gets at that same moment, in logical pixels. The pool
  /// keeps roughly its volume, which is what makes the stretch read as liquid
  /// rather than as a box being resized.
  static const double kLensSquash = 7;

  /// The travelling lens, exposed so a test can read where it actually
  /// rendered rather than inspecting the implicit animation's target.
  static const Key activeLensKey = ValueKey('nav-active-lens');

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final n = destinations.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 8, 34, 12),
      child: GlassPill(
        height: kPillHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Stack(
          children: [
            // The glass thickens under the tab you chose, and that pool glides
            // when you choose another. Deliberately EDGELESS: a radial falloff
            // to fully transparent, no outline, no bar, no dot. Every discrete
            // little marker tried here was rejected for being a small hard
            // shape competing with the glyphs; light and mass are what this
            // surface is actually made of.
            Positioned.fill(
              child: _ActiveLens(
                index: currentIndex,
                count: n,
                glass: glass,
                reduceMotion: reduceMotion,
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < n; i++)
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
          ],
        ),
      ),
    );
  }
}

/// The pool of glass under the active tab.
///
/// Explicitly driven rather than an `AnimatedAlign`, because the stretch has to
/// know how far THROUGH the journey it is and an implicit animation only
/// exposes its endpoints. Retargeting mid-flight restarts from wherever the
/// lens currently is, so hammering the tabs never teleports it.
class _ActiveLens extends StatefulWidget {
  const _ActiveLens({
    required this.index,
    required this.count,
    required this.glass,
    required this.reduceMotion,
  });

  final int index;
  final int count;
  final GlassTheme glass;
  final bool reduceMotion;

  @override
  State<_ActiveLens> createState() => _ActiveLensState();
}

class _ActiveLensState extends State<_ActiveLens>
    with SingleTickerProviderStateMixin {
  late final AnimationController _travel = AnimationController(
    vsync: this,
    duration: GlassBottomNav.kTravelDuration,
  );

  /// The journey, in slot units. [_from] is fractional whenever a new tap
  /// retargets a journey that was still in the air.
  late double _from = widget.index.toDouble();
  late double _to = widget.index.toDouble();

  @override
  void didUpdateWidget(covariant _ActiveLens old) {
    super.didUpdateWidget(old);
    // Reduce-motion is checked BEFORE the index guard: it can be switched on
    // mid-journey, and that arrives as a rebuild with an UNCHANGED index. The
    // stretch dies on its own (`build` zeroes `flight`), but the glide would
    // carry on to the end of its 300ms in flat violation of the instant-motion
    // contract.
    if (widget.reduceMotion) {
      _travel.stop();
      _from = _to = widget.index.toDouble();
      return;
    }
    if (widget.index == old.index) return;
    _from = _slot;
    _to = widget.index.toDouble();
    _travel.forward(from: 0);
  }

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  /// Where the lens is right now, in slot units.
  double get _slot =>
      _from + (_to - _from) * Curves.easeInOutCubic.transform(_travel.value);

  /// 0 at both ends of the journey, 1 at its midpoint. Driven by the RAW
  /// controller so the stretch peaks halfway through the TIME rather than
  /// halfway through the eased distance, which is where the speed actually is.
  double get _flight => math.sin(math.pi * _travel.value);

  /// The [Alignment] x that puts the lens's CENTRE on slot [slot].
  ///
  /// `Alignment` positions a child by its edges, so a wider child at the same
  /// alignment lands its centre closer to the middle of the pill — the lens
  /// would sag inward exactly when it stretches. Solving for the centre keeps
  /// the travel path straight whatever the width is.
  ///
  /// NOT separately covered by a test, deliberately. At [kLensStretch] 0.4 the
  /// sag peaks around 10px on a 104px slot and lands within a frame's worth of
  /// travel of the corrected path, so every assertion that could separate the
  /// two also failed on the correct code. The endpoints are pinned instead
  /// ("docks on the selected slot", "travels through the slot it skips"). The
  /// error scales with [kLensStretch]: at 0.8 it is 20px and visible, so keep
  /// this correction if you turn that dial up.
  double _alignmentFor(double slot, double widthFactor) {
    final slack = 1 - widthFactor;
    if (slack <= 0.001) return 0;
    return (2 * ((slot + 0.5) / widget.count - 0.5) / slack).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.count;
    if (n == 0) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _travel,
      builder: (context, _) {
        final flight = widget.reduceMotion ? 0.0 : _flight;
        // Clamped so the lens can never grow to fill the pill: past that there
        // is no slack left to position it with and the travel would stall in
        // the middle. Unreachable at three tabs; the guard is for two.
        final stretch =
            (GlassBottomNav.kLensStretch * (_to - _from).abs() * flight).clamp(
              0.0,
              math.max(0.0, 0.9 * n - 1),
            );
        final widthFactor = (1 + stretch) / n;
        final height =
            GlassBottomNav.kLensHeight - GlassBottomNav.kLensSquash * flight;
        return Align(
          alignment: Alignment(_alignmentFor(_slot, widthFactor), 0),
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            // The lens fills its slot. A bare `Center` here would hand the box
            // loose constraints and a decoration-only child collapses to zero
            // width — invisible, and the travel would be untestable because
            // there would be nothing to measure.
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 3,
                vertical: (GlassBottomNav.kPillHeight - height) / 2,
              ),
              child: DecoratedBox(
                key: GlassBottomNav.activeLensKey,
                // `activeCapsule` is the per-theme token the spec already
                // defines for exactly this ("active-tab capsule fill (bottom
                // nav)"), so each theme brings its own tuned tint rather than
                // an invented one.
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height / 2),
                  gradient: RadialGradient(
                    radius: 0.9,
                    colors: [
                      widget.glass.activeCapsule,
                      widget.glass.activeCapsule.withValues(alpha: 0),
                    ],
                    stops: const [0.1, 1],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One destination cell.
///
/// Stateful because the entrance is a one-shot that has to fire on the
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
    // The wait is the point: see [GlassBottomNav.kDrawOnStart]. The lens is
    // most of the way here before this tab answers.
    curve: const Interval(
      GlassBottomNav.kDrawOnStart,
      1,
      curve: Curves.easeOutCubic,
    ),
    // No wait on the way out — the tab you leave clears at once.
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
            // Icon and label ride the SAME animation: the tab lights up as one
            // thing when the lens gets here. Separate timers were invisible
            // while both started on the tap, but would now read as the label
            // answering before the mark it belongs to.
            child: AnimatedBuilder(
              animation: _drawOn,
              builder: (context, child) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconSelection(
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
                  const SizedBox(height: 2),
                  Text(
                    d.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color.lerp(muted, accent, _drawOn.value),
                    ),
                  ),
                ],
              ),
              child: (widget.selected ? d.activeIcon : null) ?? d.icon,
            ),
          ),
        ),
      ),
    );
  }
}
