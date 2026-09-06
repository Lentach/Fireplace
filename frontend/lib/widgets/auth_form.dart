import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';
import '../l10n/app_localizations.dart';

class AuthForm extends StatefulWidget {
  final bool isLogin;
  final Future<void> Function(String username, String password) onSubmit;

  /// Username to start with. Set when the screen sends the user from the
  /// register tab to the sign-in tab, so they never retype a name the app
  /// already knows.
  final String? initialUsername;

  /// Called on the first keystroke after a status is showing, so a message
  /// about the PREVIOUS attempt cannot sit under an edited form.
  final VoidCallback? onEdited;

  const AuthForm({
    super.key,
    required this.isLogin,
    required this.onSubmit,
    this.initialUsername,
    this.onEdited,
  });

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController =
      TextEditingController(text: widget.initialUsername ?? '');
  final _passwordController = TextEditingController();
  bool _loading = false;

  @override
  void didUpdateWidget(AuthForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prefill = widget.initialUsername;
    if (prefill != null && prefill != oldWidget.initialUsername) {
      _usernameController.text = prefill;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// The server's rule (`RegisterDto`), enforced here so the user reads it
  /// under the field instead of receiving a 400 the surface cannot explain.
  static final RegExp _usernameCharset = RegExp(r'^[a-zA-Z0-9_]+$');

  String? _validateUsername(String? value, AppLocalizations l10n) {
    final username = value?.trim() ?? '';
    if (username.isEmpty) return l10n.authUsernameRequired;
    if (widget.isLogin) return null;
    if (username.length < 3 ||
        username.length > 20 ||
        !_usernameCharset.hasMatch(username)) {
      return l10n.authUsernameRules;
    }
    return null;
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

  /// The rule stated BEFORE the user hits it. The registration rules live on
  /// the server (`RegisterDto`); a door that keeps them secret can only answer
  /// a violation with a refusal, which is what made "something went wrong" the
  /// whole conversation.
  Widget _rules(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
    child: Text(
      text,
      style: RpgTheme.bodyFont(
        fontSize: 11,
        color: FireplaceColors.of(context).mutedText,
      ),
    ),
  );

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
            style: RpgTheme.bodyFont(
              fontSize: 14,
              color: colorScheme.onSurface,
            ),
            decoration: RpgTheme.rpgInputDecoration(
              hintText: l10n.authUsernameHint,
              prefixIcon: Icons.person_outlined,
              context: context,
            ),
            onFieldSubmitted: (_) => _handleSubmit(),
            onChanged: (_) => widget.onEdited?.call(),
            validator: (value) => _validateUsername(value, l10n),
          ),
          if (!widget.isLogin) _rules(context, l10n.authUsernameRules),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            style: RpgTheme.bodyFont(
              fontSize: 14,
              color: colorScheme.onSurface,
            ),
            decoration: RpgTheme.rpgInputDecoration(
              hintText: widget.isLogin
                  ? l10n.authPasswordHint
                  : l10n.authPasswordHintRegister,
              prefixIcon: Icons.lock_outlined,
              context: context,
            ),
            obscureText: true,
            onFieldSubmitted: (_) => _handleSubmit(),
            onChanged: (_) => widget.onEdited?.call(),
            // Enforce strength only on registration; login just needs non-empty
            validator: widget.isLogin
                ? (value) => (value == null || value.isEmpty)
                      ? l10n.passwordRequired
                      : null
                : (value) => _validatePassword(value, l10n),
          ),
          if (!widget.isLogin) _rules(context, l10n.authPasswordRules),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loading ? null : _handleSubmit,
            child: _loading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      // The BUTTON's own foreground, read from the same theme
                      // that painted its fill. `colorScheme.primary` here was
                      // primary-on-primary: an invisible spinner on the themes
                      // whose buttonBg IS primary.
                      color:
                          Theme.of(context)
                              .elevatedButtonTheme
                              .style
                              ?.foregroundColor
                              ?.resolve(const {}) ??
                          colorScheme.onPrimary,
                    ),
                  )
                : Text(
                    widget.isLogin
                        ? l10n.authLoginButton
                        : l10n.authCreateAccountButton,
                  ),
          ),
        ],
      ),
    );
  }
}
