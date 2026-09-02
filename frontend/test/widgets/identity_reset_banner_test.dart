import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/connection_provider.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/identity_reset_pending_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Phase 0b reset ceremony (multi-device spec §6.2).
///
/// This banner is the entire protection: the server's delay only helps someone
/// who SEES the countdown and can stop it. So the tests hold two lines — it
/// must never appear when no ceremony is running (a permanent "someone is
/// resetting your keys" bar would train users to ignore the real one), and
/// when it does appear the cancel action must actually reach the server.
class _FakeEncryption extends EncryptionProvider {
  _FakeEncryption({this.deadline, this.locked = false});

  DateTime? deadline;
  bool locked;
  int cancelCalls = 0;
  int startCalls = 0;
  String? answer;
  int clearAnswerCalls = 0;

  @override
  String? get identityResetRequestStatus => answer;

  @override
  void clearIdentityResetRequestStatus() {
    clearAnswerCalls++;
    answer = null;
    notifyListeners();
  }

  @override
  DateTime? get identityResetDeadline => deadline;

  @override
  bool get identityUploadLocked => locked;

  @override
  void cancelIdentityReset() {
    cancelCalls++;
    deadline = null;
    notifyListeners();
  }

  @override
  void requestIdentityReset({String? recoveryPhrase}) {
    startCalls++;
    notifyListeners();
  }
}

class _FakeAuthProvider extends AuthProvider {
  @override
  UserModel? get currentUser => UserModel(id: 7, username: 'qa', tag: '0001');
}

class _FakeConnectionProvider extends ConnectionProvider {
  @override
  int? get currentUserId => 7;
}

Widget _host(EncryptionProvider encryption) {
  // The auth and connection fakes exist so the DevicesScreen the (lxvii) link
  // action pushes can build; the banner itself reads only encryption.
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuthProvider()),
      ChangeNotifierProvider<ConnectionProvider>(
        create: (_) => _FakeConnectionProvider(),
      ),
      ChangeNotifierProvider<EncryptionProvider>.value(value: encryption),
    ],
    child: MaterialApp(
      theme: RpgTheme.themeDataLight,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: IdentityResetPendingBanner()),
    ),
  );
}

void main() {
  testWidgets('renders NOTHING when no ceremony is running', (tester) async {
    await tester.pumpWidget(_host(_FakeEncryption()));

    expect(find.byIcon(Icons.lock_reset_outlined), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('warns with the remaining time and offers a one-tap cancel', (
    tester,
  ) async {
    final encryption = _FakeEncryption(
      deadline: DateTime.now().add(const Duration(hours: 71, minutes: 30)),
    );
    await tester.pumpWidget(_host(encryption));

    expect(find.byIcon(Icons.lock_reset_outlined), findsOneWidget);
    // Coarse hours, never a live seconds counter.
    expect(find.textContaining('71 hours'), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
  });

  testWidgets('cancelling reaches the provider and clears the banner', (
    tester,
  ) async {
    final encryption = _FakeEncryption(
      deadline: DateTime.now().add(const Duration(hours: 5)),
    );
    await tester.pumpWidget(_host(encryption));

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(encryption.cancelCalls, 1);
    expect(find.byIcon(Icons.lock_reset_outlined), findsNothing);
  });

  testWidgets('shows minutes once under an hour remains', (tester) async {
    final encryption = _FakeEncryption(
      deadline: DateTime.now().add(const Duration(minutes: 42)),
    );
    await tester.pumpWidget(_host(encryption));

    // Remaining time truncates down (41:59 renders as "41 minutes"), which
    // understates the window rather than overstating it — the safe direction
    // for a warning the user is meant to act on.
    expect(find.textContaining(RegExp(r'4[12] minutes')), findsOneWidget);
  });

  testWidgets('a passed deadline still shows the cancel affordance', (
    tester,
  ) async {
    // The server commits on its own clock, so a client whose countdown ran out
    // must not silently drop the banner while the cancel could still win.
    final encryption = _FakeEncryption(
      deadline: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    await tester.pumpWidget(_host(encryption));

    expect(find.byIcon(Icons.lock_reset_outlined), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
  });

  // The most damaging 0b failure mode: a user who lost their keys re-mints
  // them, the server refuses to publish because the account still holds the
  // previous identity, and nothing tells them. Peers then keep encrypting to
  // keys this device cannot read, behind a UI that claims recovery worked.
  //
  // (lxvii) clause 2: the visible way out is the LINK — the account's keys
  // exist on another device, and the ceremony disposes the refused identity.
  // The reset (which revokes every other device) is the rarer remedy and sits
  // in the disclosure.
  testWidgets('a refused key publication leads with the link', (tester) async {
    final encryption = _FakeEncryption(locked: true);
    await tester.pumpWidget(_host(encryption));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.byIcon(Icons.key_off_outlined), findsOneWidget);
    expect(find.textContaining('not published'), findsOneWidget);
    expect(find.text(l10n.devicesLinkThisDevice), findsOneWidget);
    expect(
      find.byKey(const Key('identity-reset-banner-start-reset')),
      findsNothing,
      reason: 'the reset lives in the disclosure',
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await tester.tap(find.byKey(const Key('identity-reset-banner-action')));
    await tester.pump();
    expect(navigator.canPop(), isTrue, reason: 'routes to the §5.1 host');
    expect(encryption.startCalls, 0);
    expect(encryption.cancelCalls, 0);
  });

  testWidgets('the reset is two taps away and asks for the phrase first', (
    tester,
  ) async {
    final encryption = _FakeEncryption(locked: true);
    await tester.pumpWidget(_host(encryption));

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('identity-reset-banner-start-reset')),
    );
    await tester.pumpAndSettle();

    // The recovery key is asked for FIRST: it is the difference between
    // waiting an hour and waiting three days, so the slow path must never be
    // started silently on someone who holds a phrase.
    expect(find.textContaining('recovery key'), findsWidgets);
    expect(encryption.startCalls, 0);

    await tester.tap(find.text("I don't have one"));
    await tester.pumpAndSettle();

    expect(
      encryption.startCalls,
      1,
      reason: 'declining the phrase still leaves the 72 h route open',
    );
    expect(encryption.cancelCalls, 0);
  });

  testWidgets('dismissing the phrase prompt starts nothing at all', (
    tester,
  ) async {
    final encryption = _FakeEncryption(locked: true);
    await tester.pumpWidget(_host(encryption));

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('identity-reset-banner-start-reset')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(
      encryption.startCalls,
      0,
      reason: 'backing out must not commit the account to a 72 h ceremony',
    );
  });

  testWidgets('a running ceremony takes precedence over the locked notice', (
    tester,
  ) async {
    final encryption = _FakeEncryption(
      deadline: DateTime.now().add(const Duration(hours: 3)),
      locked: true,
    );
    await tester.pumpWidget(_host(encryption));

    // Already fixing it — offering "start reset" again would be nonsense.
    expect(find.byIcon(Icons.lock_reset_outlined), findsOneWidget);
    expect(find.byIcon(Icons.key_off_outlined), findsNothing);

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(encryption.cancelCalls, 1);
    expect(encryption.startCalls, 0);
  });

  testWidgets('a refused request is said out loud, not swallowed', (
    tester,
  ) async {
    // A genuine owner recovering lost keys meets every refusal: a mistyped
    // phrase, the lockout after five of those, the post-cancel cooldown. With
    // no message the button looks broken while the account stays unreachable.
    final encryption = _FakeEncryption(locked: true)..answer = 'invalid_phrase';
    await tester.pumpWidget(_host(encryption));
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.identityResetPhraseRejected), findsOneWidget);
    // Consumed, so a rebuild cannot replay it.
    expect(encryption.clearAnswerCalls, 1);
    // Let the toast retire; it owns a dismissal timer.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the cooldown answer names the way out of it', (tester) async {
    final encryption = _FakeEncryption(locked: true)..answer = 'cooldown';
    await tester.pumpWidget(_host(encryption));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.identityResetCooldown), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
