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

  const GlassTopBar({
    super.key,
    this.leading,
    required this.title,
    this.trailing = const [],
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
        child: Row(
          children: [
            if (leading != null) ...[
              GlassCircle(
                size: capsuleHeight,
                child: Center(child: leading),
              ),
              const SizedBox(width: 10),
            ],
            // Owner ruling (2026-07-11, Telegram parity): the title floats as
            // plain text — no pill. A soft scaffold-tinted halo keeps it
            // readable when content scrolls beneath.
            Expanded(child: Center(child: _haloed(context, title))),
            if (trailing.isNotEmpty) ...[
              const SizedBox(width: 10),
              GlassPill(
                height: capsuleHeight,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: trailing),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _haloed(BuildContext context, Widget child) {
  final halo = Theme.of(context).scaffoldBackgroundColor;
  return DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(color: halo.withValues(alpha: 0.55), blurRadius: 14),
      ],
    ),
    child: child,
  );
}
