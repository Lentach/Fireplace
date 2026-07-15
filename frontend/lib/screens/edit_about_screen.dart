import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/rpg_theme.dart';
import '../widgets/glass/glass_top_bar.dart';

/// Full-screen About editor (replaces the centered autofocus dialog).
///
/// The field is anchored to the TOP of the screen on purpose: iOS WebKit
/// pans the page to reveal a focused input the keyboard would cover, and a
/// mid-screen dialog field made the whole app jump (frontend/CLAUDE.md §7
/// keyboard-inset trap). A top-anchored field is never covered, so WebKit
/// leaves the viewport alone.
///
/// Pops with the edited text (caller persists it); pops with null on cancel.
class EditAboutScreen extends StatefulWidget {
  final String? initialAbout;

  const EditAboutScreen({super.key, this.initialAbout});

  @override
  State<EditAboutScreen> createState() => _EditAboutScreenState();
}

class _EditAboutScreenState extends State<EditAboutScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialAbout ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: GlassTopBar(
        leading: IconButton(
          tooltip: l10n.userCardCancel,
          icon: Icon(Icons.close, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.userCardEditAbout,
          style: RpgTheme.bodyFont(
            fontSize: 16,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        trailing: [
          IconButton(
            tooltip: l10n.userCardSave,
            icon: Icon(Icons.check, color: theme.colorScheme.primary),
            onPressed: _save,
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.paddingOf(context).top + GlassTopBar.capsuleHeight + 32,
          20,
          0,
        ),
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 80,
          maxLines: 3,
          minLines: 1,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          style: RpgTheme.bodyFont(
            fontSize: 15,
            color: theme.colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: l10n.userCardAboutHint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }
}
