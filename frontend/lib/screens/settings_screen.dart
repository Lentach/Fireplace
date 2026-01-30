import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/rpg_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chat = context.read<ChatProvider>();

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
          padding: const EdgeInsets.all(16),
          children: [
            // Account section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: RpgTheme.boxBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: RpgTheme.border, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account',
                    style: RpgTheme.bodyFont(
                      fontSize: 16,
                      color: RpgTheme.gold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.person, color: RpgTheme.purple, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Username',
                              style: RpgTheme.bodyFont(
                                fontSize: 12,
                                color: RpgTheme.mutedText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              auth.currentUser?.username ?? 'Not set',
                              style: RpgTheme.bodyFont(
                                fontSize: 14,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.email_outlined, color: RpgTheme.purple, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Email',
                              style: RpgTheme.bodyFont(
                                fontSize: 12,
                                color: RpgTheme.mutedText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              auth.currentUser?.email ?? '',
                              style: RpgTheme.bodyFont(
                                fontSize: 14,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Logout button
            ElevatedButton(
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
          ],
        ),
      ),
    );
  }
}
