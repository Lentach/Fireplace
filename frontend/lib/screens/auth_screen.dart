import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/rpg_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_form.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'RPG CHAT',
                    style: RpgTheme.pressStart2P(
                      fontSize: 20,
                      color: RpgTheme.gold,
                    ).copyWith(
                      shadows: [
                        const Shadow(
                          offset: Offset(2, 2),
                          color: Color(0xFFAA6600),
                        ),
                        const Shadow(
                          blurRadius: 10,
                          color: Color(0x66FFCC00),
                        ),
                      ],
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the realm',
                    style: RpgTheme.bodyFont(
                      fontSize: 14,
                      color: RpgTheme.purple,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Toggle
                  Container(
                    decoration: BoxDecoration(
                      color: RpgTheme.inputBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: RpgTheme.tabBorder, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _isLogin = true);
                              authProvider.clearStatus();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _isLogin ? RpgTheme.activeTabBg : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'LOGIN',
                                style: RpgTheme.bodyFont(
                                  fontSize: 14,
                                  color: _isLogin ? RpgTheme.gold : RpgTheme.mutedText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _isLogin = false);
                              authProvider.clearStatus();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !_isLogin ? RpgTheme.activeTabBg : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'REGISTER',
                                style: RpgTheme.bodyFont(
                                  fontSize: 14,
                                  color: !_isLogin ? RpgTheme.gold : RpgTheme.mutedText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  AuthForm(
                    isLogin: _isLogin,
                    onSubmit: (email, password) async {
                      if (_isLogin) {
                        await authProvider.login(email, password);
                      } else {
                        final success = await authProvider.register(email, password);
                        if (success && mounted) {
                          setState(() => _isLogin = true);
                        }
                      }
                    },
                  ),
                  if (authProvider.statusMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      authProvider.statusMessage!,
                      textAlign: TextAlign.center,
                      style: RpgTheme.bodyFont(
                        fontSize: 13,
                        color: authProvider.isError
                            ? RpgTheme.errorColor
                            : RpgTheme.successColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
