import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// Floating glass top chrome for detail screens (accepted spec §5):
/// leading circle, expanded title pill, one trailing pill grouping actions.
/// Transparent outside the capsules; implement [PreferredSizeWidget] so it
/// drops into a `Scaffold.appBar` slot with `extendBodyBehindAppBar: true`.
class GlassTopBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? leading;
  final Widget title;
  final List<Widget> trailing;
  final double titleHorizontalInset;

  /// Telegram-style trailing avatar: rendered BARE at [capsuleHeight] so the
  /// photo fills the whole circle. Owner round-4 (2026-07-16): the glass
  /// pill around the 36px header avatar read as an uneven, non-circular
  /// "halo" — the avatar must be its own circle, no ring.
  final Widget? avatar;

  const GlassTopBar({
    super.key,
    this.leading,
    required this.title,
    this.trailing = const [],
    this.titleHorizontalInset = 106,
    this.avatar,
  });

  static const double capsuleHeight = 52;

  @override
  Size get preferredSize => const Size.fromHeight(capsuleHeight + 16);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: SizedBox(
          height: capsuleHeight,
          // Title centers against the FULL bar width (a Row slot would skew
          // it toward the narrower side — owner-reported). The Row above it
          // only hit-tests on the capsules, so title long-press still works.
          // Owner ruling (2026-07-11, round 4b): the title DOES get a glass
          // pill — "more visible with glassy bubble"; the blur lives under
          // the bubble itself, not as a band under the whole panel.
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: titleHorizontalInset,
                  ),
                  child: Center(
                    child: GlassPill(
                      height: capsuleHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Center(
                        child: FittedBox(fit: BoxFit.scaleDown, child: title),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  if (leading != null)
                    GlassCircle(
                      size: capsuleHeight,
                      child: Center(child: leading),
                    ),
                  const Spacer(),
                  if (trailing.isNotEmpty)
                    GlassPill(
                      height: capsuleHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: trailing,
                      ),
                    ),
                  if (avatar != null) ...[
                    if (trailing.isNotEmpty) const SizedBox(width: 10),
                    SizedBox.square(dimension: capsuleHeight, child: avatar),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
