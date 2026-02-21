import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/rpg_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/dialogs/reset_password_dialog.dart';
import '../widgets/dialogs/delete_account_dialog.dart';
import '../widgets/top_snackbar.dart';
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
          'Profile picture updated',
          backgroundColor: Theme.of(context).colorScheme.primary,
        );
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          context,
          'Upload failed: ${e.toString()}',
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
          'Password updated successfully',
          backgroundColor: Theme.of(context).colorScheme.primary,
        );
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          context,
          'Password reset failed: ${e.toString()}',
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
      final chat = context.read<ChatProvider>();

      await auth.deleteAccount(password);
      await chat.clearEncryptionKeys();
      chat.disconnect();

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(
          context,
          'Account deletion failed: ${e.toString()}',
          backgroundColor: const Color(0xFFFF6666),
        );
      }
    }
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
    final chat = context.read<ChatProvider>();
    final settings = context.watch<SettingsProvider>();

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Settings',
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
            _buildSettingsTile(
              icon: Icons.palette_outlined,
              title: 'Theme',
              subtitle: 'Light / Dark (Wire) / Blue',
              trailing: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'light', label: Text('Light')),
                  ButtonSegment(value: 'dark', label: Text('Dark')),
                  ButtonSegment(value: 'blue', label: Text('Blue')),
                ],
                selected: {settings.themePreference},
                onSelectionChanged: (Set<String> selected) {
                  if (selected.isNotEmpty) {
                    settings.setThemePreference(selected.first);
                  }
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),

            _buildSettingsTile(
              icon: Icons.security,
              title: 'Privacy and Safety',
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
              title: 'Blocked',
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
              title: 'Devices',
              subtitle: _deviceName ?? 'Loading...',
              trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ),

            _buildSettingsTile(
              icon: Icons.lock_reset,
              title: 'Reset Password',
              trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
              onTap: _showResetPasswordDialog,
            ),

            _buildSettingsTile(
              icon: Icons.delete_forever,
              title: 'Delete Account',
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
                  chat.disconnect();
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
                      'Logout',
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
