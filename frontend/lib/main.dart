import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/conversations_screen.dart';
import 'theme/rpg_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RpgChatApp());
}

class RpgChatApp extends StatelessWidget {
  const RpgChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'RPG Chat',
            debugShowCheckedModeBanner: false,
            theme: RpgTheme.themeData,
            darkTheme: RpgTheme.themeData, // Same theme (RPG is dark by design)
            themeMode: settings.themeMode,
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isLoggedIn) {
      return const ConversationsScreen();
    }
    return const AuthScreen();
  }
}
