import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'fcm_background_stub.dart'
    if (dart.library.io) 'services/android_fcm_local_notifications.dart'
    as fcm_background;
import 'init_file_picker_stub.dart' if (dart.library.html) 'init_file_picker_web.dart' as file_picker_init;
import 'utils/notify_conv_param_stub.dart'
    if (dart.library.html) 'utils/notify_conv_param_web.dart';
import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/connection_provider.dart';
import 'providers/conversations_provider.dart';
import 'providers/encryption_provider.dart';
import 'providers/friends_provider.dart';
import 'providers/messaging_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/main_shell.dart';
import 'services/portrait_lock_service.dart';
import 'theme/app_scroll_behavior.dart';
import 'widgets/portrait_lock_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PortraitLockService.initialize();
  file_picker_init.initFilePickerWeb();
  // Firebase + FCM background handler must be ready before [runApp] (native only).
  // Android auto-init from google-services can exist before Dart sees Firebase.apps.
  if (!kIsWeb) {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }
    FirebaseMessaging.onBackgroundMessage(
      fcm_background.firebaseMessagingBackgroundHandler,
    );
  }
  final coldStartConvId = consumeNotifyConvParam();
  stripNotifyConvParam();
  runApp(FireplaceApp(coldStartConversationId: coldStartConvId));
}

class FireplaceApp extends StatelessWidget {
  const FireplaceApp({super.key, this.coldStartConversationId});

  final int? coldStartConversationId;

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
        ChangeNotifierProvider(
          create: (_) => ConnectionProvider(
            coldStartConversationId: coldStartConversationId,
          ),
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'Fireplace',
            debugShowCheckedModeBanner: false,
            scrollBehavior: const AppScrollBehavior(),
            builder: (context, child) {
              return PortraitLockShell(
                child: child ?? const SizedBox.shrink(),
              );
            },
            theme: settings.lightTheme,
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
    final conn = context.read<ConnectionProvider>();

    // Detect logout transition (true → false) - ensure clean disconnect
    if (!auth.isLoggedIn && _previousLoggedInState) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        conn.disconnect(isLogout: true);
      });
    }

    _previousLoggedInState = auth.isLoggedIn;

    if (auth.isLoggedIn) {
      return const MainShell();
    }
    return const AuthScreen();
  }
}
