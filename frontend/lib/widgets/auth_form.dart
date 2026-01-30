import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';

class AuthForm extends StatefulWidget {
  final bool isLogin;
  final Future<void> Function(String email, String password, String? username) onSubmit;

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
  final _usernameController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
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
      widget.isLogin ? null : _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim(),
    );
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _emailController,
          style: RpgTheme.bodyFont(fontSize: 14, color: Colors.white),
          decoration: RpgTheme.rpgInputDecoration(
            hintText: 'Email',
            prefixIcon: Icons.email_outlined,
          ),
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => _handleSubmit(),
        ),
        const SizedBox(height: 16),
        if (!widget.isLogin) ...[
          TextField(
            controller: _usernameController,
            style: RpgTheme.bodyFont(fontSize: 14, color: Colors.white),
            decoration: RpgTheme.rpgInputDecoration(
              hintText: 'Username (optional)',
              prefixIcon: Icons.person_outlined,
            ),
            onSubmitted: (_) => _handleSubmit(),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _passwordController,
          style: RpgTheme.bodyFont(fontSize: 14, color: Colors.white),
          decoration: RpgTheme.rpgInputDecoration(
            hintText: widget.isLogin ? 'Password' : 'Password (min 6 chars)',
            prefixIcon: Icons.lock_outlined,
          ),
          obscureText: true,
          onSubmitted: (_) => _handleSubmit(),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _loading ? null : _handleSubmit,
          child: _loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: RpgTheme.gold,
                  ),
                )
              : Text(widget.isLogin ? 'Login' : 'Create Account'),
        ),
      ],
    );
  }
}
