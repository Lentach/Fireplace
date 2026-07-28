import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/chat_background_preference.dart';
import '../theme/glass_theme.dart';
import '../theme/rpg_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_form.dart';
import '../widgets/glass/glass_surface.dart';
import '../services/api_service.dart';
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
    // The auth screen is the app's front door and ALWAYS wears Hot Stone
    // (owner call 2026-07-28, superseding the 2026-07-18 always-Cosmic
    // ruling) — the warm-paper + ember world that is now the app default —
    // regardless of the saved chat theme. Forcing the real `themeDataLight`
    // here means the card (GlassTheme.light), inputs/button (ember primary),
    // and the plain warm-paper backdrop all come from the ONE light theme —
    // no parallel login-only palette.
    return Theme(
      data: RpgTheme.themeDataLight,
      child: Builder(builder: _buildBody),
    );
  }

  Widget _buildBody(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final fc = FireplaceColors.of(context);
    // Wordmark accent = the light glass chrome ember (GlassTheme.light
    // .onGlassAccent, deep ember #A03D0C) — reads as the brand flame against
    // the warm-paper background while FIRE stays warm near-black.
    final accent = GlassTheme.of(context).onGlassAccent;

    return Scaffold(
      body: ChatBackgroundPattern(
        // The front door always shows the plain Hot Stone paper. Chat
        // wallpaper is an authenticated per-user choice and must not leak
        // into this screen.
        layer: ChatBackgroundLayer.plain,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The landing wordmark: Archivo 900, FIRE in warm
                    // near-black (onSurface) + PLACE in the deep ember accent.
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
                                    // Dark-only neon green is illegible on
                                    // paper; this door is always light.
                                    : RpgTheme.successColorLight,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Diagnostic footer: running-bundle commit (stale-build
                    // discriminator in every victim screenshot) plus the
                    // recorded involuntary session-end reason when one exists.
                    // Deliberately NOT the async PackageInfo semver: on web
                    // that fetches the SERVER's version.json and can lie about
                    // the running bundle; the compiled commit cannot.
                    Text(
                      authProvider.lastSessionEndReason == null
                          ? ApiService.appCommit
                          : '${ApiService.appCommit} · ${l10n.sessionEndedReason(authProvider.lastSessionEndReason!)}',
                      textAlign: TextAlign.center,
                      style: RpgTheme.bodyFont(
                        fontSize: 11,
                        color: fc.mutedText.withValues(alpha: 0.7),
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
