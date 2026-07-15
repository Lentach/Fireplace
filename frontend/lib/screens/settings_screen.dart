import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/glass/glass_surface.dart';
import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/encryption_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';
import '../config/app_config.dart';
import '../config/app_version_info.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/dialogs/reset_password_dialog.dart';
import '../widgets/main_tab_screen_header.dart';
import '../widgets/dialogs/delete_account_dialog.dart';
import '../widgets/top_snackbar.dart';
import '../l10n/app_localizations.dart';
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
  String? _appVersionLine;
  late final PushService _pushService = PushService(
    ApiService(baseUrl: AppConfig.baseUrl),
  );

  @override
  void initState() {
    super.initState();
    _loadDeviceName();
    _loadAppVersion();
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

  /// Liquid Glass (owner, 2026-07-11): tiles are tinted glass cards.
  /// `blur: false` — over the flat settings background a backdrop blur is
  /// invisible and per-tile filters on a scrolling list are a perf trap;
  /// the translucent fill/border reads identically. ListTile ink still
  /// needs a [Material] ancestor inside the surface.
  Widget _settingsTileShell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(16),
        blur: false,
        shadow: false,
        child: Material(
          type: MaterialType.transparency,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(16),
          child: child,
        ),
      ),
    );
  }

  Widget _buildThemeTile(BuildContext context, SettingsProvider settings) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fc = FireplaceColors.of(context);
    final current = settings.themePreference;
    final l10n = AppLocalizations.of(context);

    Widget themeIconBtn(String value, IconData icon, String tooltip) {
      final isSelected = current == value;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: () => settings.setThemePreference(value),
          customBorder: const CircleBorder(),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.2)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? colorScheme.primary : fc.settingsTileBorder,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Icon(
              icon,
              size: 24,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return _settingsTileShell(
      ListTile(
        leading: Icon(
          Icons.palette_outlined,
          color: colorScheme.primary,
          size: 24,
        ),
        title: Text(
          AppLocalizations.of(context).theme,
          style: RpgTheme.bodyFont(
            fontSize: 14,
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            themeIconBtn('light', Icons.light_mode, l10n.themeOptionLight),
            const SizedBox(width: 8),
            themeIconBtn('teal', Icons.eco, l10n.themeOptionTealStone),
            const SizedBox(width: 8),
            themeIconBtn('dark', Icons.dark_mode, l10n.themeOptionDark),
            const SizedBox(width: 8),
            themeIconBtn('blue', Icons.water_drop, l10n.themeOptionBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageTile(BuildContext context, SettingsProvider settings) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fc = FireplaceColors.of(context);
    final current = settings.localeCode;
    final l10n = AppLocalizations.of(context);

    Widget langBtn(String code, String label) {
      final isSelected = current == code;
      return InkWell(
        onTap: () => settings.setLocalePreference(code),
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? colorScheme.primary : fc.settingsTileBorder,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: RpgTheme.bodyFont(
              fontSize: 13,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return _settingsTileShell(
      ListTile(
        leading: Icon(Icons.language, color: colorScheme.primary, size: 24),
        title: Text(
          l10n.language,
          style: RpgTheme.bodyFont(
            fontSize: 14,
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            langBtn('pl', l10n.languagePolish),
            const SizedBox(width: 8),
            langBtn('en', l10n.languageEnglish),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? textColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return _settingsTileShell(
      ListTile(
        leading: Icon(icon, color: colorScheme.primary, size: 24),
        title: Text(
          title,
          style: RpgTheme.bodyFont(
            fontSize: 14,
            color: textColor ?? colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: RpgTheme.bodyFont(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        trailing: trailing,
        onTap: onTap,
        enabled: onTap != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final conn = context.read<ConnectionProvider>();
    final settings = context.watch<SettingsProvider>();

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MainTabScreenHeader(title: AppLocalizations.of(context).settings),
          Expanded(
            child: SafeArea(
              top: false,
              bottom: false,
              child: ListView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.only(
                  top: 16,
                  bottom: MediaQuery.paddingOf(context).bottom + 16,
                ),
                children: [
                  // Header Section
                  Column(
                    children: [
                      const SizedBox(height: 24),
                      Stack(
                        children: [
                          AvatarCircle(
                            displayName: auth.currentUser?.username ?? '',
                            radius: 60,
                            profilePictureUrl:
                                auth.currentUser?.profilePictureUrl,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _openMyProfile,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: theme.colorScheme.surface,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.person_outline,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${auth.currentUser?.username ?? 'Hero'}#${auth.currentUser?.tag ?? '0000'}',
                        style: RpgTheme.bodyFont(
                          fontSize: 20,
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),

                  // Settings Tiles
                  _buildThemeTile(context, settings),
                  _buildLanguageTile(context, settings),

                  _buildSettingsTile(
                    icon: Icons.security,
                    title: AppLocalizations.of(context).privacyAndSafety,
                    trailing: Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PrivacySafetyScreen(),
                        ),
                      );
                    },
                  ),

                  _buildSettingsTile(
                    icon: Icons.block,
                    title: AppLocalizations.of(context).blocked,
                    trailing: Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BlockedUsersScreen(),
                        ),
                      );
                    },
                  ),

                  _buildSettingsTile(
                    icon: Icons.devices,
                    title: AppLocalizations.of(context).devices,
                    subtitle:
                        _deviceName ??
                        AppLocalizations.of(context).devicesLoading,
                    trailing: Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),

                  if (kIsWeb)
                    _buildSettingsTile(
                      icon: Icons.notifications_active,
                      title: AppLocalizations.of(context).webPushEnableTitle,
                      subtitle: AppLocalizations.of(
                        context,
                      ).webPushEnableSubtitle,
                      trailing: Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      onTap: _enableWebPushNotifications,
                    ),

                  _buildSettingsTile(
                    icon: Icons.lock_reset,
                    title: AppLocalizations.of(context).resetPassword,
                    trailing: Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: _showResetPasswordDialog,
                  ),

                  _buildSettingsTile(
                    icon: Icons.delete_forever,
                    title: AppLocalizations.of(context).deleteAccount,
                    trailing: Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: _showDeleteAccountDialog,
                    textColor: theme.colorScheme.error,
                  ),

                  const SizedBox(height: 24),

                  if (_appVersionLine != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          Text(
                            AppLocalizations.of(context).settingsAppVersion,
                            style: RpgTheme.bodyFont(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _appVersionLine!,
                            style: RpgTheme.bodyFont(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.85),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                  if (_appVersionLine != null) const SizedBox(height: 16),

                  // E2E key-loss warning — shown right above logout (the uninstall/clear-data danger point).
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      AppLocalizations.of(context).uninstallWarning,
                      style: RpgTheme.bodyFont(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Logout Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ElevatedButton(
                      onPressed: () {
                        conn.disconnect(isLogout: true);
                        auth.logout();
                        if (Navigator.of(context).canPop()) {
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.logout, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.of(context).logout,
                            style: RpgTheme.bodyFont(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
