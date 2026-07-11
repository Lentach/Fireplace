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
/// 34px sides / 12px bottom, active tab highlighted with a capsule in
/// `GlassTheme.activeCapsule`, labels/icons in on-glass colors.
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

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 8, 34, 12),
      child: GlassPill(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(child: _item(context, glass, i)),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, GlassTheme glass, int index) {
    final d = destinations[index];
    final selected = index == currentIndex;
    final color = selected ? glass.onGlassAccent : glass.onGlassMuted;
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
          onTap: () => onTap(index),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? glass.activeCapsule : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
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
            ),
          ),
        ),
      ),
    );
  }
}
