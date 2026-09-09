import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/conversations_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/passcode_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/screens/conversations_screen.dart';
import 'package:fireplace/screens/recovery_key_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/utils/backup_nudge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/passcode_fakes.dart';

/// Multi-device spec §12 amendment (lxxxiii): the phrase is offered once at
/// the door (clause 1) and nudged on Czaty for any account the server reports
/// as backup-less (clause 3). Falsifications F39/F40 live here.
class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider({required this.fresh});

  bool fresh;

  @override
  UserModel? get currentUser =>
      UserModel(id: 7, username: 'Marta', tag: '0007');

  @override
  String? get token => 'test-token';

  @override
  Future<void> ensureSessionReady() async {}

  @override
  bool consumeFreshRegistration() {
    final value = fresh;
    fresh = false;
    return value;
  }
}

class _FakeConnectionProvider extends ConnectionProvider {
  @override
  Future<void> connect(
    int userId,
    String token,
    String baseUrl, {
    bool immediate = false,
  }) async {}
}

const _nudge = Key('backup-nudge');
const _dismiss = Key('backup-nudge-dismiss');
const _later = Key('recovery-key-later');

Future<
  ({EncryptionProvider encryption, SettingsProvider settings})
> _pump(
  WidgetTester tester, {
  bool fresh = false,
  double width = 400,
}) async {
  final encryption = EncryptionProvider();
  final settings = SettingsProvider(initialThemePreference: 'light');
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => _FakeAuthProvider(fresh: fresh),
        ),
        ChangeNotifierProvider<ConnectionProvider>(
          create: (_) => _FakeConnectionProvider(),
        ),
        ChangeNotifierProvider(create: (_) => FriendsProvider()),
        ChangeNotifierProvider(
          create: (_) => ConversationsProvider()..setCurrentUserId(7),
        ),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<EncryptionProvider>.value(value: encryption),
        ChangeNotifierProvider(create: (_) => MessagingProvider()),
        ChangeNotifierProvider(
          create: (_) => PasscodeProvider(
            store: MemoryPasscodeStore(),
            kdf: FakePasscodeKdf(),
          ),
        ),
      ],
      child: MaterialApp(
        theme: RpgTheme.themeDataLight,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            disableAnimations: true,
          ),
          child: const ConversationsScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (encryption: encryption, settings: settings);
}

/// The server's word on the phrase, as `ownKeyBundleStatus` carries it.
/// `hasIdentityBackup` defaults to the same value; clause 4's cases split them.
void _status(
  EncryptionProvider encryption, {
  bool? hasRecoveryPhrase,
  bool? hasIdentityBackup,
}) {
  encryption.onOwnKeyBundleStatus({
    'exists': true,
    'hasRecoveryPhrase': ?hasRecoveryPhrase,
    'hasIdentityBackup': ?(hasIdentityBackup ?? hasRecoveryPhrase),
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('shouldShowBackupNudge (clause 3 predicate)', () {
    final now = DateTime.utc(2026, 9, 9, 12);

    test('only an EXPLICIT false shows; unknown and true never do', () {
      for (final hasPhrase in [null, true]) {
        expect(
          shouldShowBackupNudge(
            hasRecoveryPhrase: hasPhrase,
            dismissedAt: null,
            now: now,
          ),
          isFalse,
          reason: 'hasRecoveryPhrase=$hasPhrase',
        );
      }
      expect(
        shouldShowBackupNudge(
          hasRecoveryPhrase: false,
          dismissedAt: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('F40: a snooze hides it for exactly seven days, then it is back', () {
      final dismissed = now.subtract(const Duration(days: 7));
      expect(
        shouldShowBackupNudge(
          hasRecoveryPhrase: false,
          dismissedAt: dismissed.add(const Duration(seconds: 1)),
          now: now,
        ),
        isFalse,
        reason: 'one second short of a week: still snoozed',
      );
      expect(
        shouldShowBackupNudge(
          hasRecoveryPhrase: false,
          dismissedAt: dismissed,
          now: now,
        ),
        isTrue,
        reason: 'a week later the line is due again',
      );
    });
  });

  group('SettingsProvider snooze', () {
    test('persists per account and reloads across a restart', () async {
      final settings = SettingsProvider(initialThemePreference: 'light');
      final at = DateTime.fromMillisecondsSinceEpoch(1_760_000_000_000);
      await settings.snoozeBackupNudge(7, now: at);
      expect(settings.backupNudgeDismissedAt, at);

      final fresh = SettingsProvider(initialThemePreference: 'light');
      await fresh.loadBackupNudge(8);
      expect(fresh.backupNudgeDismissedAt, isNull,
          reason: 'another account on the same install is not snoozed');
      await fresh.loadBackupNudge(7);
      expect(fresh.backupNudgeDismissedAt, at);
    });
  });

  for (final width in [400.0, 1000.0]) {
    testWidgets(
      'clause 3 (width $width): the line follows the server flag and the X '
      'snoozes it',
      (tester) async {
        final h = await _pump(tester, width: width);
        expect(find.byKey(_nudge), findsNothing, reason: 'unknown shows nothing');

        _status(h.encryption, hasRecoveryPhrase: true);
        await tester.pump();
        expect(find.byKey(_nudge), findsNothing);

        _status(h.encryption, hasRecoveryPhrase: false);
        await tester.pump();
        expect(find.byKey(_nudge), findsOneWidget);

        await tester.tap(find.byKey(_dismiss));
        await tester.pump();
        expect(find.byKey(_nudge), findsNothing);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('backup_nudge_dismissed_at_7'), isNotNull);

        // "Done removes it": the server ack flips the flag.
        h.settings.snoozeBackupNudge(7, now: DateTime(2020)).ignore();
        await tester.pump();
        expect(find.byKey(_nudge), findsOneWidget, reason: 'old snooze expired');
        h.encryption.onRecoveryKeySet(const {'success': true});
        await tester.pump();
        expect(find.byKey(_nudge), findsNothing);
      },
    );
  }

  testWidgets('clause 3: tapping the line opens the recovery-key screen '
      'without a "later" action', (tester) async {
    final h = await _pump(tester);
    _status(h.encryption, hasRecoveryPhrase: false);
    await tester.pump();
    await tester.tap(find.byKey(_nudge));
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryKeyScreen), findsOneWidget);
    expect(find.byKey(_later), findsNothing);
  });

  testWidgets('clause 1 / F39: a fresh registration is offered the phrase only '
      'once the server says there is no backup; "Później" snoozes the line',
      (tester) async {
    final h = await _pump(tester, fresh: true);
    expect(find.byType(RecoveryKeyScreen), findsNothing,
        reason: 'unknown: no offer yet');

    _status(h.encryption, hasRecoveryPhrase: false);
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryKeyScreen), findsOneWidget);
    expect(find.byKey(_later), findsOneWidget);

    await tester.tap(find.byKey(_later));
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryKeyScreen), findsNothing);
    expect(find.byKey(_nudge), findsNothing,
        reason: 'a line under the screen just declined is a nag');
    expect(h.settings.backupNudgeDismissedAt, isNotNull);

    // The offer fires once: a later status does not re-open it.
    _status(h.encryption, hasRecoveryPhrase: false);
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryKeyScreen), findsNothing);
  });

  testWidgets('clause 1 / F39: an account the server reports WITH a backup is '
      'never offered the screen, fresh or not', (tester) async {
    final h = await _pump(tester, fresh: true);
    _status(h.encryption, hasRecoveryPhrase: true);
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryKeyScreen), findsNothing);
  });

  testWidgets('clause 1: without a fresh registration the flag alone opens '
      'nothing', (tester) async {
    final h = await _pump(tester);
    _status(h.encryption, hasRecoveryPhrase: false);
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryKeyScreen), findsNothing);
    expect(find.byKey(_nudge), findsOneWidget);
  });

  testWidgets('clause 4 / F44: a pre-(lxxviii) verifier-only phrase '
      '(hasRecoveryPhrase true, hasIdentityBackup false) gets NO line and NO '
      'offer', (tester) async {
    final h = await _pump(tester, fresh: true);
    // goonboy's shape, prod id 48.
    _status(h.encryption, hasRecoveryPhrase: true, hasIdentityBackup: false);
    await tester.pumpAndSettle();
    expect(find.byKey(_nudge), findsNothing);
    expect(find.byType(RecoveryKeyScreen), findsNothing);
  });

  testWidgets('clause 4 / F45: a status WITHOUT the field (older server) is '
      'UNKNOWN — nothing renders even when hasIdentityBackup is false',
      (tester) async {
    final h = await _pump(tester, fresh: true);
    h.encryption.onOwnKeyBundleStatus(const {
      'exists': true,
      'hasIdentityBackup': false,
    });
    await tester.pumpAndSettle();
    expect(find.byKey(_nudge), findsNothing);
    expect(find.byType(RecoveryKeyScreen), findsNothing);
  });

  testWidgets('clause 4: the door warns that new words REPLACE an enrolled '
      'phrase, and only then', (tester) async {
    final h = await _pump(tester);
    _status(h.encryption, hasRecoveryPhrase: false);
    await tester.pump();
    await tester.tap(find.byKey(_nudge));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recovery-key-replaces-existing')),
        findsNothing, reason: 'no phrase yet: nothing to replace');

    // The server now says a phrase exists (e.g. enrolled from another tab).
    _status(h.encryption, hasRecoveryPhrase: true, hasIdentityBackup: false);
    await tester.pump();
    expect(find.byKey(const Key('recovery-key-replaces-existing')),
        findsOneWidget);
  });
}
