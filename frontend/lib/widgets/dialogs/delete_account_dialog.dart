import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rpg_theme.dart';
import '../glass/glass_dialog.dart';

class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_passwordController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final fc = FireplaceColors.of(context);

    return GlassDialog(
      maxWidth: 400,
      title: Text(l10n.deleteAccountDialogTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Destructive warning: theme-aware tile tokens (the old
            // hardwired *Dark tokens broke light-theme contrast).
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: fc.settingsTileBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: fc.settingsTileBorder),
              ),
              child: Text(
                l10n.deleteAccountWarning,
                style: RpgTheme.bodyFont(
                  color: colorScheme.primary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.enterPasswordToConfirm,
                labelStyle: RpgTheme.bodyFont(color: fc.mutedText),
                filled: true,
                fillColor: fc.inputBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: fc.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: fc.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
              style: RpgTheme.bodyFont(color: colorScheme.onSurface),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l10n.passwordRequired;
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.delete)),
      ],
    );
  }
}
