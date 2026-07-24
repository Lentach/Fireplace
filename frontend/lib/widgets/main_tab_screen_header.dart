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

  /// Wrap [leading] in a glass circle (the Chats avatar). Contacts opts out:
  /// its magnifier is a bare icon mirroring the bare trailing control.
  final bool leadingGlass;

  /// Replaces the whole capsule row while keeping the shared geometry
  /// (safe area + insets + capsule height) — the Contacts search field.
  final Widget? custom;

  const MainTabScreenHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
    this.leadingGlass = true,
  }) : custom = null;

  /// Row-replacing variant: the caller owns everything inside the capsule
  /// band, the header still owns the geometry.
  const MainTabScreenHeader.custom({super.key, required Widget child})
    : title = '',
      leading = null,
      trailing = null,
      leadingGlass = true,
      custom = child;

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
          child: custom ?? _buildCapsuleRow(context),
        ),
      ),
    );
  }

  Widget _buildCapsuleRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        // Full-width centered title, immune to asymmetric side
        // controls (leading avatar circle vs bare trailing icon).
        Positioned.fill(
          child: IgnorePointer(
            child: Padding(
              // Reserve the widest control footprint on BOTH sides so
              // a long title can never sit under a control.
              padding: const EdgeInsets.symmetric(
                horizontal: capsuleHeight + 10,
              ),
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
          ),
        ),
        if (leading != null)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: leadingGlass
                ? GlassCircle(
                    size: capsuleHeight,
                    child: Center(child: leading),
                  )
                : Center(child: leading),
          ),
        if (trailing != null)
          // Bare icon, no glass circle (owner round-5: "remove halo
          // around plus icon"); centered against the capsule height.
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(child: trailing),
          ),
      ],
    );
  }
}
