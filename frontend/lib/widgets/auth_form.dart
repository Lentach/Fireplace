import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';

class AuthForm extends StatefulWidget {
  final bool isLogin;
  final Future<void> Function(String email, String password) onSubmit;

  const AuthForm({
    super.key,
    required this.isLogin,
    required this.onSubmit,
  });

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      return;
    }
    setState(() => _loading = true);
    await widget.onSubmit(
      _emailController.text.trim(),
      _passwordController.text,
    );
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '\u{1F4E7} EMAIL',
          style: RpgTheme.pressStart2P(fontSize: 8, color: RpgTheme.labelText),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _emailController,
          style: RpgTheme.pressStart2P(fontSize: 9, color: Colors.white),
          decoration: RpgTheme.rpgInputDecoration(hintText: 'hero@quest.com'),
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => _handleSubmit(),
        ),
        const SizedBox(height: 14),
        Text(
          '\u{1F511} PASSWORD${widget.isLogin ? '' : ' (min 6)'}',
          style: RpgTheme.pressStart2P(fontSize: 8, color: RpgTheme.labelText),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordController,
          style: RpgTheme.pressStart2P(fontSize: 9, color: Colors.white),
          decoration: RpgTheme.rpgInputDecoration(hintText: '******'),
          obscureText: true,
          onSubmitted: (_) => _handleSubmit(),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _loading ? null : _handleSubmit,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: RpgTheme.buttonBg,
              border: Border.all(color: RpgTheme.gold, width: 3),
            ),
            alignment: Alignment.center,
            child: _loading
                ? Text(
                    'LOADING...',
                    style: RpgTheme.pressStart2P(fontSize: 10, color: RpgTheme.gold),
                  )
                : Text(
                    widget.isLogin ? '\u25B6 ENTER REALM' : '\u2726 CREATE HERO',
                    style: RpgTheme.pressStart2P(fontSize: 10, color: RpgTheme.gold),
                  ),
          ),
        ),
      ],
    );
  }
}
