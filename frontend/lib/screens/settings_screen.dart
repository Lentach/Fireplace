import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/rpg_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/dialogs/reset_password_dialog.dart';
import '../widgets/dialogs/delete_account_dialog.dart';
import '../widgets/dialogs/profile_picture_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _deviceName;
  bool _activeStatus = true;

  @override
  void initState() {
    super.initState();
    _loadDeviceName();
  }

  Future<void> _loadDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();
    String name = 'Unknown Device';

    try {
      if (kIsWeb) {
        name = 'Web Browser';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        name = '${androidInfo.manufacturer} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        name = '${iosInfo.name} (${iosInfo.systemName})';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        name = windowsInfo.computerName;
      } else if (Platform.isLinux) {
        name = 'Linux Device';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        name = macInfo.computerName;
      }
    } catch (e) {
      debugPrint('Error loading device name: $e');
    }

    if (mounted) {
      setState(() => _deviceName = name);
    }
  }

  Future<void> _showProfilePictureDialog() async {
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => const ProfilePictureDialog(),
    );

    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(source: source);
    if (image == null || !mounted) return;

    try {
      final auth = context.read<AuthProvider>();
      await auth.updateProfilePicture(File(image.path));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile picture updated',
              style: RpgTheme.bodyFont(color: Colors.white),
            ),
            backgroundColor: RpgTheme.purple,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Upload failed: ${e.toString()}',
              style: RpgTheme.bodyFont(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFFF6666),
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Password updated successfully',
              style: RpgTheme.bodyFont(color: Colors.white),
            ),
            backgroundColor: RpgTheme.purple,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Password reset failed: ${e.toString()}',
              style: RpgTheme.bodyFont(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFFF6666),
          ),
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
      chat.disconnect();

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Account deletion failed: ${e.toString()}',
              style: RpgTheme.bodyFont(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFFF6666),
          ),
        );
      }
    }
  }

  Future<void> _updateActiveStatus(bool value) async {
    setState(() => _activeStatus = value);
    try {
      final chat = context.read<ChatProvider>();
      chat.socket.updateActiveStatus(value);
    } catch (e) {
      setState(() => _activeStatus = !value); // Revert on error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update status: ${e.toString()}',
              style: RpgTheme.bodyFont(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFFF6666),
          ),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: RpgTheme.boxBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RpgTheme.border, width: 1.5),
      ),
      child: ListTile(
        leading: Icon(icon, color: RpgTheme.purple, size: 24),
        title: Text(
          title,
          style: RpgTheme.bodyFont(
            fontSize: 14,
            color: textColor ?? RpgTheme.textColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: RpgTheme.bodyFont(
                  fontSize: 12,
                  color: RpgTheme.mutedText,
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

    return Scaffold(
      backgroundColor: RpgTheme.background,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: RpgTheme.bodyFont(
            fontSize: 18,
            color: RpgTheme.gold,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: RpgTheme.boxBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: RpgTheme.gold),
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
                      email: auth.currentUser?.email ?? '',
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
                            color: RpgTheme.purple,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: RpgTheme.background,
                              width: 3,
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
                  auth.currentUser?.username ?? 'Hero',
                  style: RpgTheme.bodyFont(
                    fontSize: 20,
                    color: RpgTheme.textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  auth.currentUser?.email ?? '',
                  style: RpgTheme.bodyFont(
                    fontSize: 14,
                    color: RpgTheme.mutedText,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),

            // Settings Tiles
            _buildSettingsTile(
              icon: Icons.circle,
              title: 'Active Status',
              trailing: Switch(
                value: _activeStatus,
                onChanged: _updateActiveStatus,
                activeTrackColor: RpgTheme.purple,
              ),
            ),

            _buildSettingsTile(
              icon: Icons.dark_mode,
              title: 'Dark Mode',
              trailing: DropdownButton<String>(
                value: settings.darkModePreference,
                onChanged: (value) {
                  if (value != null) {
                    settings.setDarkModePreference(value);
                  }
                },
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('System')),
                  DropdownMenuItem(value: 'light', child: Text('Light')),
                  DropdownMenuItem(value: 'dark', child: Text('Dark')),
                ],
                underline: const SizedBox(),
                style: RpgTheme.bodyFont(
                  fontSize: 14,
                  color: RpgTheme.textColor,
                ),
                dropdownColor: RpgTheme.boxBg,
              ),
            ),

            _buildSettingsTile(
              icon: Icons.security,
              title: 'Privacy and Safety',
              trailing: Icon(Icons.chevron_right, color: RpgTheme.mutedText),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Coming soon',
                      style: RpgTheme.bodyFont(color: Colors.white),
                    ),
                    backgroundColor: RpgTheme.purple,
                  ),
                );
              },
            ),

            _buildSettingsTile(
              icon: Icons.devices,
              title: 'Devices',
              subtitle: _deviceName ?? 'Loading...',
              trailing: Icon(Icons.chevron_right, color: RpgTheme.mutedText),
            ),

            _buildSettingsTile(
              icon: Icons.lock_reset,
              title: 'Reset Password',
              trailing: Icon(Icons.chevron_right, color: RpgTheme.mutedText),
              onTap: _showResetPasswordDialog,
            ),

            _buildSettingsTile(
              icon: Icons.delete_forever,
              title: 'Delete Account',
              trailing: Icon(Icons.chevron_right, color: RpgTheme.mutedText),
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
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: RpgTheme.logoutRed,
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
