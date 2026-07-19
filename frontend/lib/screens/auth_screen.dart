import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/glass_theme.dart';
import '../theme/rpg_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/auth_form.dart';
import '../widgets/glass/glass_surface.dart';
import '../widgets/chat_background_pattern.dart';
import '../l10n/app_localizations.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;

  Widget _tab(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final muted = FireplaceColors.of(context).mutedText;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: RpgTheme.bodyFont(
              fontSize: 14,
              color: selected ? scheme.primary : muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The auth screen is the app's front door and ALWAYS wears the cosmic
    // world (owner call 2026-07-18) — the same starfield + palette a visitor
    // just scrolled through on the landing black-hole journey — regardless of
    // the saved chat theme. Forcing the real `themeDataCosmic` here means the
    // card (GlassTheme.cosmic), inputs/button (accentCosmic), and the animated
    // starfield (CosmicBackdrop, rendered by ChatBackgroundPattern) all come
    // from the ONE cosmic theme — no parallel login-only palette.
    return Theme(
      data: RpgTheme.themeDataCosmic,
      child: Builder(builder: _buildBody),
    );
  }

  Widget _buildBody(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final fc = FireplaceColors.of(context);
    // Wordmark accent = the app's cosmic-chrome blue (settings icons/toggles),
    // the exact tone the owner picked from the variant board — a hair lighter
    // than colorScheme.primary (#8FD8FF).
    final accent = GlassTheme.of(context).onGlassAccent;

    return Scaffold(
      body: ChatBackgroundPattern(
        // Front door shows the starfield for everyone; a returning cosmic user
        // who turned the animated field off for battery keeps that choice.
        enabled: settings.themePreference == 'cosmic'
            ? settings.cosmicStarfield
            : true,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The landing wordmark: Archivo 900, FIRE white + PLACE in
                    // the cosmic-chrome accent (owner pick F6 + N split).
                    Text.rich(
                      TextSpan(
                        text: 'FIRE',
                        style: GoogleFonts.archivo(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.8,
                          height: 1,
                          color: scheme.onSurface,
                        ),
                        children: [
                          TextSpan(
                            text: 'PLACE',
                            style: GoogleFonts.archivo(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.8,
                              height: 1,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.authTagline,
                      textAlign: TextAlign.center,
                      style: RpgTheme.bodyFont(
                        fontSize: 14,
                        color: fc.mutedText,
                      ),
                    ),
                    const SizedBox(height: 32),
                    GlassSurface(
                      borderRadius: BorderRadius.circular(20),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: fc.inputBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: fc.tabBorder,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                _tab(context, l10n.authLoginTab, _isLogin, () {
                                  setState(() => _isLogin = true);
                                  authProvider.clearStatus();
                                }),
                                _tab(
                                  context,
                                  l10n.authRegisterTab,
                                  !_isLogin,
                                  () {
                                    setState(() => _isLogin = false);
                                    authProvider.clearStatus();
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          AuthForm(
                            isLogin: _isLogin,
                            onSubmit: (username, password) async {
                              if (_isLogin) {
                                await authProvider.login(username, password);
                              } else {
                                final success = await authProvider.register(
                                  username,
                                  password,
                                );
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
                                    ? scheme.error
                                    : RpgTheme.successColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
