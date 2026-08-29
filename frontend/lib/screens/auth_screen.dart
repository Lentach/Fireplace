import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/chat_background_preference.dart';
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

  /// The status line to show, localized here because the provider has no
  /// locale. A code always wins over [AuthProvider.statusMessage]: the latter
  /// is the pre-localized channel used for the device-revoked notice, and the
  /// provider clears one whenever it sets the other.
  String? _statusText(AuthProvider auth, AppLocalizations l10n) {
    return switch (auth.statusCode) {
      AuthStatusCode.savedSessionUnreadable =>
        l10n.authStatusSavedSessionUnreadable,
      AuthStatusCode.registerSucceeded => l10n.authStatusRegisterSucceeded,
      AuthStatusCode.serverUnreachable => l10n.authStatusServerUnreachable,
      AuthStatusCode.unexpectedError => l10n.authStatusUnexpectedError,
      null => auth.statusMessage,
    };
  }

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
                    // The landing wordmark: Archivo 900, UMBRA in warm
                    // near-black (onSurface). The old FIRE/PLACE two-tone
                    // split does not map to a single word.
                    Text(
                      'UMBRA',
                      style: GoogleFonts.archivo(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.8,
                        height: 1,
                        color: scheme.onSurface,
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
                          // The provider holds no locale, so it reports a CODE
                          // and this layer picks the words. `statusMessage` is
                          // the pre-localized channel (the device-revoked
                          // notice), so a code always wins when both are set.
                          if (_statusText(authProvider, l10n) case final text?)
                            ...[
                              const SizedBox(height: 16),
                              Text(
                                text,
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
