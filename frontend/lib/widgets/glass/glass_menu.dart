import 'package:flutter/material.dart';

import '../../theme/rpg_theme.dart';
import 'glass_surface.dart';

/// One entry in a [showGlassMenu] popup.
class GlassMenuEntry<T> {
  final T value;

  /// Row content — usually a [Text] or an icon+label [Row]. Plain text inherits
  /// an on-glass style; a destructive entry is tinted with the error color.
  final Widget child;
  final bool destructive;

  const GlassMenuEntry({
    required this.value,
    required this.child,
    this.destructive = false,
  });
}

/// Glass-surfaced replacement for `showMenu` / `PopupMenuButton` (Liquid Glass;
/// SPEC §9 lists popup menus as framework Material; glassing them was noted
/// there as a deferred follow-up). Keeps popup semantics — it is a real
/// [PopupRoute], so system back and a barrier tap dismiss it, and its layout
/// delegate keeps it clear of screen edges — but the surface is a floating
/// [GlassSurface] instead of an opaque Material menu.
///
/// Anchor it to the widget that triggered it by passing that widget's
/// `context`; the menu opens just below, right-aligned to the trigger.
Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required List<GlassMenuEntry<T>> entries,
}) {
  final navigator = Navigator.of(context);
  final button = context.findRenderObject()! as RenderBox;
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final Offset topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
  final Rect anchor = topLeft & button.size;

  return navigator.push(
    _GlassMenuRoute<T>(
      anchor: anchor,
      overlaySize: overlay.size,
      entries: entries,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
    ),
  );
}

class _GlassMenuRoute<T> extends PopupRoute<T> {
  _GlassMenuRoute({
    required this.anchor,
    required this.overlaySize,
    required this.entries,
    required this.barrierLabel,
    required this.capturedThemes,
  });

  final Rect anchor;
  final Size overlaySize;
  final List<GlassMenuEntry<T>> entries;
  final CapturedThemes capturedThemes;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 140);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    // Scale/fade only the menu body, INSIDE the layout, so the anchored
    // position (from the delegate) never shifts while it animates in.
    return CustomSingleChildLayout(
      delegate: _GlassMenuLayout(anchor: anchor, overlaySize: overlaySize),
      child: capturedThemes.wrap(
        FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            alignment: Alignment.topRight,
            child: _GlassMenuBody<T>(entries: entries),
          ),
        ),
      ),
    );
  }
}

/// Positions the menu below the anchor, right edge aligned to the anchor's
/// right, clamped inside the overlay with an 8px margin; flips above the anchor
/// when there is not enough room below.
class _GlassMenuLayout extends SingleChildLayoutDelegate {
  _GlassMenuLayout({required this.anchor, required this.overlaySize});

  final Rect anchor;
  final Size overlaySize;
  static const double _margin = 8;
  static const double _gap = 6;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      constraints.biggest,
    ).deflate(const EdgeInsets.all(_margin));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x = anchor.right - childSize.width;
    final belowY = anchor.bottom + _gap;
    final aboveY = anchor.top - _gap - childSize.height;
    double y = (belowY + childSize.height <= size.height - _margin)
        ? belowY
        : (aboveY >= _margin ? aboveY : belowY);

    x = x.clamp(_margin, size.width - _margin - childSize.width);
    y = y.clamp(_margin, size.height - _margin - childSize.height);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_GlassMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor || overlaySize != oldDelegate.overlaySize;
}

class _GlassMenuBody<T> extends StatelessWidget {
  const _GlassMenuBody({required this.entries});

  final List<GlassMenuEntry<T>> entries;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GlassSurface(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in entries)
                InkWell(
                  onTap: () => Navigator.of(context).pop(entry.value),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: DefaultTextStyle.merge(
                          style: RpgTheme.bodyFont(
                            fontSize: 14,
                            color: entry.destructive
                                ? colorScheme.error
                                : colorScheme.onSurface,
                          ),
                          child: IconTheme.merge(
                            data: IconThemeData(
                              size: 20,
                              color: entry.destructive
                                  ? colorScheme.error
                                  : colorScheme.onSurface,
                            ),
                            child: entry.child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
