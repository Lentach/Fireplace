import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_background_preference.dart';
import '../theme/rpg_theme.dart';
import '../widgets/appearance_preview.dart';
import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/encryption_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';
import '../config/app_config.dart';
import '../config/app_version_info.dart';
import '../models/user_model.dart';
import '../widgets/local_node_core.dart';
import '../widgets/settings_console.dart';
import '../widgets/dialogs/reset_password_dialog.dart';
import '../widgets/main_tab_screen_header.dart';
import '../widgets/dialogs/delete_account_dialog.dart';
import '../widgets/top_snackbar.dart';
import '../l10n/app_localizations.dart';
import 'appearance_screen.dart';
import 'blocked_users_screen.dart';
import 'privacy_safety_screen.dart';
import '../utils/instant_opaque_route.dart';
import 'user_card_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _deviceName;
  static final Uri _aboutFireplaceUri = Uri.parse(
    'https://fireplace.ignorelist.com/welcome/',
  );
  String? _appVersionLine;
  late final PushService _pushService = PushService(
    ApiService(baseUrl: AppConfig.baseUrl),
  );

  @override
  void initState() {
    super.initState();
    _loadDeviceName();
    _loadAppVersion();
    final userId = context.read<AuthProvider>().currentUser?.id;
    if (userId != null) {
      context.read<SettingsProvider>().loadChatBackground(userId);
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await AppVersionInfo.load();
      if (mounted) {
        setState(() => _appVersionLine = info.displayLine);
      }
    } catch (e) {
      debugPrint('Error loading app version: $e');
    }
  }

  Future<void> _loadDeviceName() async {
    String name = 'Unknown Device';

    try {
      if (kIsWeb) {
        name = 'Web Browser';
      } else {
        // Native platforms: show generic name (DeviceInfoPlugin could be used for real name)
        name = 'Native Device';
      }
    } catch (e) {
      debugPrint('Error loading device name: $e');
    }

    if (mounted) {
      setState(() => _deviceName = name);
    }
  }

  void _openMyProfile() {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    Navigator.of(context).push(
      instantOpaqueRoute(
        builder: (_) => UserCardScreen(
          data: UserCardVisualData.fromUser(
            user,
            isSelf: true,
            hasConversation: false,
          ),
        ),
      ),
    );
  }

  void _openAboutFireplace() {
    launchUrl(
      _aboutFireplaceUri,
      mode: LaunchMode.externalApplication,
    ).ignore();
  }

  Future<void> _showResetPasswordDialog() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const ResetPasswordDialog(),
    );

    if (result == null || !mounted) return;

    try {
      final auth = context.read<AuthProvider>();
      await auth.resetPassword(result['oldPassword']!, result['newPassword']!);

      if (mounted) {
        showTopSnackBar(
          context,
          AppLocalizations.of(context).passwordUpdatedSuccessfully,
          backgroundColor: Theme.of(context).colorScheme.primary,
        );
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          context,
          '${AppLocalizations.of(context).passwordResetFailed}: ${e.toString()}',
          backgroundColor: Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  Future<void> _showDeleteAccountDialog() async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) => const DeleteAccountDialog(),
    );

    if (password == null || !mounted) return;

    try {
      final auth = context.read<AuthProvider>();
      final enc = context.read<EncryptionProvider>();
      final conn = context.read<ConnectionProvider>();

      await auth.deleteAccount(password);
      await enc.clearEncryptionKeys();
      conn.disconnect(isLogout: true);

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          context,
          '${AppLocalizations.of(context).accountDeletionFailed}: ${e.toString()}',
          backgroundColor: Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  Future<void> _enableWebPushNotifications() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    final result = await _pushService.requestWebPushFromUserGesture(token);
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    switch (result.status) {
      case WebPushRequestStatus.subscribed:
        showTopSnackBar(
          context,
          l10n.webPushEnabled,
          backgroundColor: Theme.of(context).colorScheme.primary,
        );
        break;
      case WebPushRequestStatus.denied:
        showTopSnackBar(
          context,
          l10n.webPushPermissionDenied,
          backgroundColor: Theme.of(context).colorScheme.error,
        );
        break;
      case WebPushRequestStatus.requiresStandalone:
        showTopSnackBar(
          context,
          l10n.webPushInstallRequired,
          backgroundColor: Theme.of(context).colorScheme.error,
        );
        break;
      case WebPushRequestStatus.unsupported:
        showTopSnackBar(
          context,
          l10n.webPushNotSupported,
          backgroundColor: Theme.of(context).colorScheme.error,
        );
        break;
      case WebPushRequestStatus.noChange:
        showTopSnackBar(
          context,
          l10n.webPushNoChanges,
          backgroundColor: Theme.of(context).colorScheme.primary,
        );
        break;
      case WebPushRequestStatus.failed:
        showTopSnackBar(
          context,
          '${l10n.webPushEnableFailed}: ${result.details ?? ''}',
          backgroundColor: Theme.of(context).colorScheme.error,
        );
        break;
    }
  }

  /// The Appearance row's "glyph" is the live theme itself — the real
  /// [AppearancePreview] miniature, hex-clipped so it reads as a terminal
  /// like every other row.
  ///
  /// It is drawn OVERSIZED and centre-cropped on purpose: the miniature
  /// paints its own radius-12 rounded border, and at anything near the hex's
  /// own size that border cuts visible arcs across the interior. Blown up
  /// past the clip, only the themed surface and its background pattern
  /// survive — which is the part that actually identifies the theme at 38px.
  Widget _appearancePreviewInHex(SettingsProvider settings) {
    return OverflowBox(
      maxWidth: 92,
      maxHeight: 58,
      child: AppearancePreview(
        themeData: settings.themeData,
        background: settings.resolvedChatBackground,
        width: 92,
        height: 58,
      ),
    );
  }

  Widget _buildAppearanceRow(BuildContext context, SettingsProvider settings) {
    final l10n = AppLocalizations.of(context);
    final themeName = switch (settings.themePreference) {
      'light' => l10n.appearanceThemeLight,
      'teal' => l10n.appearanceThemeTeal,
      'dark' => l10n.appearanceThemeDark,
      'cosmic' => l10n.appearanceThemeCosmic,
      _ => l10n.appearanceThemeBlue,
    };
    final backgroundName = switch (settings.chatBackground) {
      ChatBackgroundPreference.themeDefault =>
        settings.themePreference == 'cosmic'
            ? l10n.appearanceBackgroundStarfield
            : l10n.appearanceBackgroundPlain,
      ChatBackgroundPreference.plain => l10n.appearanceBackgroundPlain,
      ChatBackgroundPreference.glyphs => l10n.appearanceBackgroundGlyphs,
    };

    return SettingsConsoleRow(
      glyph: ConsoleGlyph.appearance,
      leadingOverride: _appearancePreviewInHex(settings),
      title: l10n.appearance,
      subtitle: l10n.appearanceSummary(themeName, backgroundName),
      onTap: () {
        final userId = context.read<AuthProvider>().currentUser?.id;
        if (userId == null) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AppearanceScreen(userId: userId)),
        );
      },
    );
  }

  Widget _buildLanguageRow(BuildContext context, SettingsProvider settings) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final current = settings.localeCode;

    // The chip shows the CODE, not the language name. At 320px with a 1.6
    // text scale "Polski"+"Angielski" is ~210px of non-flexible trailing,
    // which collapses the title to a one-letter-per-line column. The full
    // name stays on the semantics node so screen readers still announce it.
    Widget chip(String code, String label) {
      final selected = current == code;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            onTap: () => settings.setLocalePreference(code),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primary.withValues(alpha: 0.16)
                    : null,
                border: Border.all(
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.28),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                code.toUpperCase(),
                style: RpgTheme.bodyFont(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ).copyWith(letterSpacing: 1.2),
              ),
            ),
          ),
        ),
      );
    }

    // No row-level onTap: the chips are the affordance, so the row itself
    // must not be a button that does nothing.
    return SettingsConsoleRow(
      glyph: ConsoleGlyph.language,
      title: l10n.language,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip('pl', l10n.languagePolish),
          chip('en', l10n.languageEnglish),
        ],
      ),
    );
  }

  /// The local node: the same round reticle the Contacts core uses. Tapping
  /// it opens your own user card, which is what the old floating badge did.
  Widget _buildLocalNode(BuildContext context, UserModel? user) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final name = user?.username ?? 'Hero';

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Column(
        children: [
          Semantics(
            button: true,
            label: l10n.contactNetworkYouLocalNode,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: _openMyProfile,
              child: LocalNodeCore(
                radius: 46,
                displayName: name,
                avatarUrl: user?.profilePictureUrl,
                initialsFontSize: 24,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$name#${user?.tag ?? '0000'}',
            style: RpgTheme.bodyFont(
              fontSize: 18,
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.contactNetworkLocalNode,
            style: RpgTheme.bodyFont(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ).copyWith(letterSpacing: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutFireplaceLink() {
    final colorScheme = Theme.of(context).colorScheme;
    final label = AppLocalizations.of(context).settingsAboutFireplace;

    return Semantics(
      button: true,
      link: true,
      label: label,
      child: Align(
        child: InkWell(
          key: const Key('settings-about-fireplace-link'),
          borderRadius: BorderRadius.circular(8),
          onTap: _openAboutFireplace,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'FIREPLACE',
                      style: RpgTheme.bodyFont(
                        fontSize: 10,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ).copyWith(letterSpacing: 1.6),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 1,
                      height: 12,
                      color: colorScheme.outlineVariant,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: RpgTheme.bodyFont(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.north_east_rounded,
                      size: 13,
                      color: colorScheme.onSurfaceVariant,
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final conn = context.read<ConnectionProvider>();
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MainTabScreenHeader(title: l10n.settings),
          Expanded(
            child: SafeArea(
              top: false,
              bottom: false,
              child: ListView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom + 16,
                ),
                children: [
                  _buildLocalNode(context, auth.currentUser),

                  SettingsSectionCaption(
                    label: l10n.settingsSectionPreferences,
                  ),
                  _buildAppearanceRow(context, settings),
                  _buildLanguageRow(context, settings),

                  SettingsSectionCaption(label: l10n.settingsSectionSecurity),
                  SettingsConsoleRow(
                    glyph: ConsoleGlyph.privacy,
                    title: l10n.privacyAndSafety,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PrivacySafetyScreen(),
                        ),
                      );
                    },
                  ),
                  SettingsConsoleRow(
                    glyph: ConsoleGlyph.blocked,
                    title: l10n.blocked,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BlockedUsersScreen(),
                        ),
                      );
                    },
                  ),
                  // No onTap today - this row reports the device, it does not
                  // navigate. Kept non-interactive rather than faking a target.
                  SettingsConsoleRow(
                    glyph: ConsoleGlyph.devices,
                    title: l10n.devices,
                    subtitle: _deviceName ?? l10n.devicesLoading,
                  ),
                  if (kIsWeb)
                    SettingsConsoleRow(
                      glyph: ConsoleGlyph.push,
                      title: l10n.webPushEnableTitle,
                      subtitle: l10n.webPushEnableSubtitle,
                      onTap: _enableWebPushNotifications,
                    ),

                  SettingsSectionCaption(label: l10n.settingsSectionSession),
                  SettingsConsoleRow(
                    glyph: ConsoleGlyph.password,
                    title: l10n.resetPassword,
                    onTap: _showResetPasswordDialog,
                  ),
                  SettingsConsoleRow(
                    glyph: ConsoleGlyph.deleteNode,
                    title: l10n.deleteAccount,
                    edge: ConsoleRowEdge.danger,
                    onTap: _showDeleteAccountDialog,
                  ),
                  SettingsConsoleRow(
                    glyph: ConsoleGlyph.logout,
                    title: l10n.logout,
                    edge: ConsoleRowEdge.accent,
                    onTap: () {
                      conn.disconnect(isLogout: true);
                      auth.logout();
                      if (Navigator.of(context).canPop()) {
                        Navigator.pop(context);
                      }
                    },
                  ),

                  const SizedBox(height: 28),
                  _buildAboutFireplaceLink(),

                  if (_appVersionLine != null) ...[
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          Text(
                            l10n.settingsAppVersion,
                            textAlign: TextAlign.center,
                            style: RpgTheme.bodyFont(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _appVersionLine!,
                            textAlign: TextAlign.center,
                            style: RpgTheme.bodyFont(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  // E2E key-loss warning - the uninstall/clear-data danger
                  // point. It stays at the very bottom, under everything.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      l10n.uninstallWarning,
                      textAlign: TextAlign.center,
                      style: RpgTheme.bodyFont(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
