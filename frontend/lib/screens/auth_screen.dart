import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/rpg_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/rpg_box.dart';
import '../widgets/tab_bar_widget.dart';
import '../widgets/auth_form.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  int _activeTab = 0; // 0 = login, 1 = register

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: RpgTheme.background,
      body: Center(
          child: RpgBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '\u2694\uFE0F RPG CHAT \u2694\uFE0F',
                  style: RpgTheme.pressStart2P(
                    fontSize: 16,
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
                  '~ Enter the realm ~',
                  style: RpgTheme.pressStart2P(
                    fontSize: 8,
                    color: RpgTheme.purple,
                  ),
                ),
                const SizedBox(height: 20),
                RpgTabBar(
                  activeIndex: _activeTab,
                  labels: const ['LOGIN', 'REGISTER'],
                  onTap: (i) {
                    setState(() => _activeTab = i);
                    authProvider.clearStatus();
                  },
                ),
                const SizedBox(height: 16),
                if (_activeTab == 0)
                  AuthForm(
                    isLogin: true,
                    onSubmit: (email, password) async {
                      await authProvider.login(email, password);
                    },
                  )
                else
                  AuthForm(
                    isLogin: false,
                    onSubmit: (email, password) async {
                      final success =
                          await authProvider.register(email, password);
                      if (success && mounted) {
                        setState(() => _activeTab = 0);
                      }
                    },
                  ),
                if (authProvider.statusMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    authProvider.statusMessage!,
                    textAlign: TextAlign.center,
                    style: RpgTheme.pressStart2P(
                      fontSize: 8,
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
    );
  }
}
