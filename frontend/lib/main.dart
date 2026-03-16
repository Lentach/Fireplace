import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'init_file_picker_stub.dart' if (dart.library.html) 'init_file_picker_web.dart' as file_picker_init;
import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/connection_provider.dart';
import 'providers/conversations_provider.dart';
import 'providers/encryption_provider.dart';
import 'providers/friends_provider.dart';
import 'providers/messaging_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/main_shell.dart';
import 'theme/rpg_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  file_picker_init.initFilePickerWeb();
  runApp(const FireplaceApp());
  // Firebase init in background — app shows immediately; push ready shortly after
  Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
      .catchError((_) {});
}

class FireplaceApp extends StatelessWidget {
  const FireplaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => EncryptionProvider()),
        ChangeNotifierProvider(create: (_) => FriendsProvider()),
        ChangeNotifierProvider(create: (_) => ConversationsProvider()),
        ChangeNotifierProvider(create: (_) => MessagingProvider()),
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        // ChatProvider is a thin facade delegating to the new providers.
        // Kept for backward-compat with existing screens until they migrate.
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'Fireplace',
            debugShowCheckedModeBanner: false,
            theme: RpgTheme.themeDataLight,
            darkTheme: settings.darkTheme,
            themeMode: settings.themeMode,
            locale: settings.locale,
            supportedLocales: const [
              Locale('pl'),
              Locale('en'),
            ],
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
            ],
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _previousLoggedInState = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chat = context.read<ChatProvider>();

    // Detect logout transition (true → false) - ensure clean disconnect
    if (!auth.isLoggedIn && _previousLoggedInState) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        chat.disconnect();
      });
    }

    _previousLoggedInState = auth.isLoggedIn;

    if (auth.isLoggedIn) {
      return const MainShell();
    }
    return const AuthScreen();
  }
}
