import 'dart:ui' show SemanticsRole;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../theme/rpg_theme.dart';
import 'glass_surface.dart';

/// Glass-surfaced replacement for [AlertDialog] (Liquid Glass; SPEC §9 lists
/// dialogs as framework Material; glassing them was a deferred follow-up).
/// Drop-in for the common
/// AlertDialog fields — pass it straight to
/// `showDialog(builder: (_) => GlassDialog(...))`. The modal barrier behind it
/// is the backdrop the blur samples, so it reads as glass over the dimmed app.
///
/// Title/content plain [Text] children inherit sensible on-glass styles via
/// [DefaultTextStyle]; a child that sets its own style (e.g. an error-colored
/// action label) keeps it.
class GlassDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;

  /// Caps the dialog width on wide (desktop) layouts. Applied INSIDE the
  /// [Dialog] because route pages are laid out with tight full-screen
  /// constraints — an outer ConstrainedBox around the dialog is a no-op.
  final double? maxWidth;

  const GlassDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Mirror AlertDialog's scoped/named-route semantics + role (the base
    // Dialog omits them) so screen readers announce this as a dialog route.
    // Platform label matches AlertDialog: null on iOS/macOS, localized else.
    final String? label = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => null,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.windows => MaterialLocalizations.of(
        context,
      ).alertDialogLabel,
    };

    Widget dialogChild = GlassSurface(
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            DefaultTextStyle.merge(
              style: RpgTheme.bodyFont(
                fontSize: 18,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              child: title!,
            ),
          if (content != null) ...[
            if (title != null) const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: DefaultTextStyle.merge(
                  style: RpgTheme.bodyFont(
                    fontSize: 14,
                    color: colorScheme.onSurface,
                  ),
                  child: content!,
                ),
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: actions,
            ),
          ],
        ],
      ),
    );

    if (maxWidth != null) {
      dialogChild = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: dialogChild,
      );
    }

    if (label != null) {
      dialogChild = Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        namesRoute: true,
        label: label,
        child: dialogChild,
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      semanticsRole: SemanticsRole.alertDialog,
      child: dialogChild,
    );
  }
}
