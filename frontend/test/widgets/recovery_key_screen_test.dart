import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/encryption_provider.dart';
import 'package:fireplace/screens/recovery_key_screen.dart';
import 'package:fireplace/services/recovery_phrase.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Recovery-key enrolment (multi-device spec §6.2.1).
///
/// Two properties carry the whole feature: the phrase must be a real BIP39
/// phrase the server will later recognise, and it must never be written to
/// this device — a phrase stored here is destroyed by exactly the event it
/// exists to recover from.
class _FakeEncryption extends EncryptionProvider {
  String? sent;
  bool? result;

  @override
  bool? get recoveryKeySetResult => result;

  @override
  void setRecoveryKey(String phrase) {
    sent = phrase;
    result = true;
    notifyListeners();
  }

  @override
  void clearRecoveryKeySetResult() {}
}

Widget _host(EncryptionProvider encryption) {
  return ChangeNotifierProvider<EncryptionProvider>.value(
    value: encryption,
    child: MaterialApp(
      theme: RpgTheme.themeDataLight,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const RecoveryKeyScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows no phrase until one is explicitly generated', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_FakeEncryption()));

    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('generating shows twelve real BIP39 words', (tester) async {
    await tester.pumpWidget(_host(_FakeEncryption()));

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final shown = tester.widget<SelectableText>(find.byType(SelectableText));
    final phrase = RecoveryPhrase.normalize(shown.data ?? '');
    expect(phrase.split(' ').length, 12);
    expect(
      RecoveryPhrase.isValid(phrase),
      isTrue,
      reason: 'a phrase the server cannot verify is worse than none',
    );
  });

  testWidgets('confirming sends exactly the phrase that was shown', (
    tester,
  ) async {
    final encryption = _FakeEncryption();
    await tester.pumpWidget(_host(encryption));

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    final shown = tester.widget<SelectableText>(find.byType(SelectableText));
    final displayed = RecoveryPhrase.normalize(shown.data ?? '');

    await tester.tap(find.byType(FilledButton).last);
    await tester.pump(const Duration(milliseconds: 200));

    expect(encryption.sent, displayed);
    // Drain the confirmation snackbar's own timer so the test does not end
    // with it pending.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('the phrase is never written to local storage', (tester) async {
    final encryption = _FakeEncryption();
    await tester.pumpWidget(_host(encryption));

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    final shown = tester.widget<SelectableText>(find.byType(SelectableText));
    final displayed = RecoveryPhrase.normalize(shown.data ?? '');

    await tester.tap(find.byType(FilledButton).last);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      expect(
        prefs.get(key).toString(),
        isNot(contains(displayed.split(' ').first)),
        reason: 'storing the phrase loses it to the very event it recovers from',
      );
    }
  });
}
