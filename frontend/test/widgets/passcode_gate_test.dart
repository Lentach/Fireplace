import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/providers/passcode_provider.dart';
import 'package:fireplace/services/passcode_store.dart';
import 'package:fireplace/screens/passcode_unlock_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/passcode_gate.dart';
import 'package:provider/provider.dart';

import '../support/passcode_fakes.dart';

/// Stands in for the whole logged-in app. If this text is reachable while the
/// passcode is locked, the feature has failed.
const _guarded = Key('guarded-app');

Widget _host(PasscodeProvider passcode) => ChangeNotifierProvider.value(
  value: passcode,
  child: MaterialApp(
    theme: RpgTheme.themeDataLight,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: const PasscodeGate(
      child: Scaffold(body: Text('SECRET CHATS', key: _guarded)),
    ),
  ),
);

void main() {
  late MemoryPasscodeStore store;
  late FakePasscodeKdf kdf;
  late PasscodeProvider passcode;
  late int now;

  setUp(() {
    store = MemoryPasscodeStore();
    kdf = FakePasscodeKdf();
    now = 1757000000000;
    passcode = PasscodeProvider(store: store, kdf: kdf, nowMs: () => now);
  });

  testWidgets('with no passcode configured the app is shown', (tester) async {
    await passcode.initialize();
    await tester.pumpWidget(_host(passcode));
    await tester.pumpAndSettle();

    expect(find.byKey(_guarded), findsOneWidget);
    expect(find.text('SECRET CHATS'), findsOneWidget);
  });

  testWidgets('before initialize resolves, the app is NOT painted',
      (tester) async {
    // PasscodeLockState.unknown: painting the shell here would flash the chat
    // list for a frame on every cold start of a locked app.
    await tester.pumpWidget(_host(passcode));
    await tester.pump();

    expect(find.text('SECRET CHATS'), findsNothing);
  });

  testWidgets('while locked the app is hidden behind the lock screen',
      (tester) async {
    await passcode.initialize();
    await passcode.enable(passcode: '1234', mode: PasscodeMode.digits4);
    passcode.lockNow();

    await tester.pumpWidget(_host(passcode));
    await tester.pumpAndSettle();

    expect(find.text('SECRET CHATS'), findsNothing);
    expect(find.byKey(const Key('passcode-dots')), findsOneWidget);
  });

  testWidgets('the right code reveals the app; the wrong one does not',
      (tester) async {
    await passcode.initialize();
    await passcode.enable(passcode: '1234', mode: PasscodeMode.digits4);
    passcode.lockNow();
    await tester.pumpWidget(_host(passcode));
    await tester.pumpAndSettle();

    for (final d in '9999'.split('')) {
      await tester.tap(find.byKey(Key('passcode-key-$d')));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('SECRET CHATS'), findsNothing);
    expect(find.byKey(const Key('passcode-error')), findsOneWidget);

    for (final d in '1234'.split('')) {
      await tester.tap(find.byKey(Key('passcode-key-$d')));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('SECRET CHATS'), findsOneWidget);
  });

  testWidgets('the guarded subtree keeps its state across a lock',
      (tester) async {
    // The lock must not tear down the app: disposing MainShell would drop the
    // socket, the open conversation and every in-flight send.
    await passcode.initialize();
    await passcode.enable(passcode: '1234', mode: PasscodeMode.digits4);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: passcode,
        child: MaterialApp(
          theme: RpgTheme.themeDataLight,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const PasscodeGate(child: _Counter()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('counter-bump')));
    await tester.pump();
    expect(find.text('taps: 1'), findsOneWidget);

    passcode.lockNow();
    await tester.pumpAndSettle();
    expect(find.text('taps: 1'), findsNothing);

    for (final d in '1234'.split('')) {
      await tester.tap(find.byKey(Key('passcode-key-$d')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('taps: 1'), findsOneWidget,
        reason: 'state survived: the subtree was hidden, not rebuilt');
  });
  testWidgets('the forgot-passcode door asks for confirmation first',
      (tester) async {
    // Only reachable while locked, and it must never fire on a single tap:
    // it logs the user out.
    await passcode.initialize();
    await passcode.enable(passcode: '1234', mode: PasscodeMode.digits4);
    passcode.lockNow();

    var recoveries = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: passcode,
        child: MaterialApp(
          theme: RpgTheme.themeDataLight,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: PasscodeUnlockScreen(onForgot: () async => recoveries++),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passcode-forgot-confirm')), findsNothing);

    await tester.tap(find.byKey(const Key('passcode-forgot-link')));
    await tester.pumpAndSettle();
    expect(recoveries, 0, reason: 'opening the door must not log anyone out');

    await tester.tap(find.byKey(const Key('passcode-forgot-confirm')));
    await tester.pumpAndSettle();

    expect(recoveries, 1);
  });

}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text('taps: $_taps'),
        TextButton(
          key: const Key('counter-bump'),
          onPressed: () => setState(() => _taps++),
          child: const Text('bump'),
        ),
      ],
    ),
  );
}
