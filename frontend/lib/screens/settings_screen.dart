import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/rpg_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/encryption_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/dialogs/reset_password_dialog.dart';
import '../widgets/dialogs/delete_account_dialog.dart';
import '../widgets/top_snackbar.dart';
import '../l10n/app_localizations.dart';
import 'blocked_users_screen.dart';
import 'privacy_safety_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _deviceName;

  @override
  void initState() {
    super.initState();
    _loadDeviceName();
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

  Future<void> _showProfilePictureDialog() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;

    try {
      final auth = context.read<AuthProvider>();
      await auth.updateProfilePicture(image);

      if (mounted) {
        showTopSnackBar(
          context,
          AppLocalizations.of(context).profilePictureUpdated,
          backgroundColor: Theme.of(context).colorScheme.primary,
        );
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          context,
          '${AppLocalizations.of(context).uploadFailed}: ${e.toString()}',
          backgroundColor: const Color(0xFFFF6666),
        );
      }
    }
  }

  Future<void> _showResetPasswordDialog() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const ResetPasswordDialog(),
    );

    if (result == null || !mounted) return;

    try {
      final auth = context.read<AuthProvider>();
      await auth.resetPassword(
        result['oldPassword']!,
        result['newPassword']!,
      );

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
          backgroundColor: const Color(0xFFFF6666),
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
          backgroundColor: const Color(0xFFFF6666),
        );
      }
    }
  }

  Widget _buildThemeTile(BuildContext context, SettingsProvider settings) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fc = FireplaceColors.of(context);
    final current = settings.themePreference;

    Widget themeIconBtn(String value, IconData icon) {
      final isSelected = current == value;
      return InkWell(
        onTap: () => settings.setThemePreference(value),
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.primary.withValues(alpha: 0.2) : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? colorScheme.primary : fc.settingsTileBorder,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Icon(
            icon,
            size: 24,
            color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
      decoration: BoxDecoration(
        color: fc.settingsTileBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fc.settingsTileBorder, width: 1.2),
      ),
      child: ListTile(
        leading: Icon(Icons.palette_outlined, color: colorScheme.primary, size: 24),
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
            themeIconBtn('light', Icons.light_mode),
            const SizedBox(width: 8),
            themeIconBtn('dark', Icons.dark_mode),
            const SizedBox(width: 8),
            themeIconBtn('blue', Icons.water_drop),
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
            color: isSelected ? colorScheme.primary.withValues(alpha: 0.2) : Colors.transparent,
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
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
      decoration: BoxDecoration(
        color: fc.settingsTileBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fc.settingsTileBorder, width: 1.2),
      ),
      child: ListTile(
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
    final fc = FireplaceColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
      decoration: BoxDecoration(
        color: fc.settingsTileBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: fc.settingsTileBorder,
          width: 1.2,
        ),
      ),
      child: ListTile(
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
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          AppLocalizations.of(context).settings,
          style: RpgTheme.pressStart2P(
            fontSize: 12,
            color: theme.colorScheme.primary,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.primary),
      ),
      body: SafeArea(
        child: ListView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 16),
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
                      profilePictureUrl: auth.currentUser?.profilePictureUrl,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _showProfilePictureDialog,
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
                            Icons.camera_alt,
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
              trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
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
              trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
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
              subtitle: _deviceName ?? AppLocalizations.of(context).devicesLoading,
              trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ),

            _buildSettingsTile(
              icon: Icons.lock_reset,
              title: AppLocalizations.of(context).resetPassword,
              trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
              onTap: _showResetPasswordDialog,
            ),

            _buildSettingsTile(
              icon: Icons.delete_forever,
              title: AppLocalizations.of(context).deleteAccount,
              trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
              onTap: _showDeleteAccountDialog,
              textColor: const Color(0xFFFF6666),
            ),

            const SizedBox(height: 24),

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
    );
  }
}
