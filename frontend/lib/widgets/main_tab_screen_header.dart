import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';
import 'glass/glass_surface.dart';

/// Shared floating top chrome for main tabs (Chat, Contacts, Settings):
/// Liquid Glass capsules (accepted spec §5) — optional leading circle, a
/// centered title pill, optional trailing circle. Transparent outside the
/// capsules so content can scroll behind.
class MainTabScreenHeader extends StatelessWidget {
  final String title;
  final Widget? leading;
  final Widget? trailing;

  const MainTabScreenHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
  });

  /// Capsule height (spec §5).
  static const double capsuleHeight = 52;

  /// Horizontal inset of the floating row (spec §5).
  static const double horizontalPadding = 14;

  /// Vertical gap between the safe-area top and the capsules.
  static const double topGap = 8;

  /// Total header footprint below the safe-area top; scrollables that run
  /// behind the header pad their top by safe-top + this.
  static const double clearance = topGap + capsuleHeight + 8;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          horizontalPadding,
          topGap,
          horizontalPadding,
          0,
        ),
        child: SizedBox(
          height: capsuleHeight,
          child: Row(
            children: [
              if (leading != null) ...[
                GlassCircle(
                  size: capsuleHeight,
                  child: Center(child: leading),
                ),
                const SizedBox(width: 10),
              ],
              // Owner ruling (2026-07-11): plain floating title, no pill.
              Expanded(
                child: Center(
                  child: Text(
                    title,
                    style:
                        RpgTheme.screenHeaderTitle(
                          color: colorScheme.onSurface,
                          fontSize: 17,
                        ).copyWith(
                          shadows: [
                            Shadow(
                              color: Theme.of(
                                context,
                              ).scaffoldBackgroundColor.withValues(alpha: 0.7),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                GlassCircle(
                  size: capsuleHeight,
                  child: Center(child: trailing),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
