import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'contacts_screen.dart';
import 'conversations_screen.dart';
import 'settings_screen.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/friends_provider.dart';
import '../widgets/top_snackbar.dart';

/// Shell after login: bottom nav with Conversations, Contacts, Settings.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final conn = context.read<ConnectionProvider>();
    final auth = context.read<AuthProvider>();
    if (auth.currentUser == null || auth.token == null) return;
    conn.ensureReconnectIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Consumer<FriendsProvider>(
      builder: (context, friends, _) {
        if (friends.pendingFriendAcceptedByName != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final name = context.read<FriendsProvider>().consumePendingFriendAccepted();
            if (name != null && context.mounted) {
              showTopSnackBar(
                context,
                '$name accepted your friend request',
                backgroundColor: Colors.green,
              );
            }
          });
        }
        return _buildScaffold(context, theme, colorScheme);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          ConversationsScreen(
            onAvatarTap: () => setState(() => _selectedIndex = 2),
          ),
          const ContactsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: theme.colorScheme.surface,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline, size: 24),
            activeIcon: _FilledChatBubbleWithLines(
              iconColor: colorScheme.primary,
              lineColor: colorScheme.onPrimary,
            ),
            label: AppLocalizations.of(context).chat,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: AppLocalizations.of(context).contacts,
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: AppLocalizations.of(context).settings,
          ),
        ],
      ),
    );
  }
}

/// Filled chat bubble icon with three horizontal lines inside (Apple-like minimalist style).
class _FilledChatBubbleWithLines extends StatelessWidget {
  final Color iconColor;
  final Color lineColor;

  const _FilledChatBubbleWithLines({
    required this.iconColor,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(24, 24),
      painter: _ChatBubblePainter(
        bubbleColor: iconColor,
        lineColor: lineColor,
      ),
    );
  }
}

/// Custom painter for clean Apple-style chat bubble with 3 lines.
class _ChatBubblePainter extends CustomPainter {
  final Color bubbleColor;
  final Color lineColor;

  _ChatBubblePainter({
    required this.bubbleColor,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = bubbleColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Draw rounded rectangle bubble (main body)
    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(2, 3, size.width - 4, size.height - 8),
      const Radius.circular(11),
    );
    canvas.drawRRect(bubbleRect, paint);

    // Draw tail (small triangle at bottom left)
    final tailPath = Path()
      ..moveTo(6, size.height - 5)
      ..lineTo(3, size.height - 2)
      ..lineTo(8, size.height - 5)
      ..close();
    canvas.drawPath(tailPath, paint);

    // Draw three horizontal lines inside (white/contrast color)
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    const lineWidth = 10.0;
    final centerX = size.width / 2;
    final startY = 9.0;
    const lineSpacing = 3.0;

    // Line 1
    canvas.drawLine(
      Offset(centerX - lineWidth / 2, startY),
      Offset(centerX + lineWidth / 2, startY),
      linePaint,
    );

    // Line 2
    canvas.drawLine(
      Offset(centerX - lineWidth / 2, startY + lineSpacing),
      Offset(centerX + lineWidth / 2, startY + lineSpacing),
      linePaint,
    );

    // Line 3
    canvas.drawLine(
      Offset(centerX - lineWidth / 2, startY + lineSpacing * 2),
      Offset(centerX + lineWidth / 2, startY + lineSpacing * 2),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(_ChatBubblePainter oldDelegate) {
    return oldDelegate.bubbleColor != bubbleColor ||
        oldDelegate.lineColor != lineColor;
  }
}
