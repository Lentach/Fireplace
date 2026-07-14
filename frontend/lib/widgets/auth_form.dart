import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';
import '../l10n/app_localizations.dart';

class AuthForm extends StatefulWidget {
  final bool isLogin;
  final Future<void> Function(String username, String password) onSubmit;

  const AuthForm({
    super.key,
    required this.isLogin,
    required this.onSubmit,
  });

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value, AppLocalizations l10n) {
    if (value == null || value.isEmpty) return l10n.passwordRequired;
    if (value.length < 8) return l10n.passwordMinLength;
    if (!RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).+$').hasMatch(value)) {
      return l10n.passwordMustContain;
    }
    return null;
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await widget.onSubmit(
        _usernameController.text.trim(),
        _passwordController.text,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _usernameController,
            style: RpgTheme.bodyFont(fontSize: 14, color: colorScheme.onSurface),
            decoration: RpgTheme.rpgInputDecoration(
              hintText: l10n.authUsernameHint,
              prefixIcon: Icons.person_outlined,
              context: context,
            ),
            onFieldSubmitted: (_) => _handleSubmit(),
            validator: (value) =>
                (value == null || value.isEmpty) ? l10n.authUsernameRequired : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            style: RpgTheme.bodyFont(fontSize: 14, color: colorScheme.onSurface),
            decoration: RpgTheme.rpgInputDecoration(
              hintText:
                  widget.isLogin ? l10n.authPasswordHint : l10n.authPasswordHintRegister,
              prefixIcon: Icons.lock_outlined,
              context: context,
            ),
            obscureText: true,
            onFieldSubmitted: (_) => _handleSubmit(),
            // Enforce strength only on registration; login just needs non-empty
            validator: widget.isLogin
                ? (value) =>
                    (value == null || value.isEmpty) ? l10n.passwordRequired : null
                : (value) => _validatePassword(value, l10n),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loading ? null : _handleSubmit,
            child: _loading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                : Text(widget.isLogin ? l10n.authLoginButton : l10n.authCreateAccountButton),
          ),
        ],
      ),
    );
  }
}
