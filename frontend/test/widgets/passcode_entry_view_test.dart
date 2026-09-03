import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/services/passcode_store.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/passcode_entry_view.dart';

Widget _host(Widget child) => MaterialApp(
  theme: RpgTheme.themeDataLight,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Future<void> _tapDigits(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.byKey(Key('passcode-key-$d')));
    await tester.pump();
  }
}

void main() {
  group('PasscodeEntryView numeric', () {
    testWidgets('shows one empty dot per expected digit', (tester) async {
      await tester.pumpWidget(
        _host(
          PasscodeEntryView(
            mode: PasscodeMode.digits6,
            title: 'Enter passcode',
            onSubmit: (_) async {},
          ),
        ),
      );

      expect(find.byKey(const Key('passcode-dot-empty-0')), findsOneWidget);
      expect(find.byKey(const Key('passcode-dot-empty-5')), findsOneWidget);
      expect(find.byKey(const Key('passcode-dot-empty-6')), findsNothing);
    });

    testWidgets('typing fills the dots left to right', (tester) async {
      await tester.pumpWidget(
        _host(
          PasscodeEntryView(
            mode: PasscodeMode.digits4,
            title: 'Enter passcode',
            onSubmit: (_) async {},
          ),
        ),
      );

      await _tapDigits(tester, '12');

      expect(find.byKey(const Key('passcode-dot-filled-0')), findsOneWidget);
      expect(find.byKey(const Key('passcode-dot-filled-1')), findsOneWidget);
      expect(find.byKey(const Key('passcode-dot-empty-2')), findsOneWidget);
      expect(find.byKey(const Key('passcode-dot-empty-3')), findsOneWidget);
    });

    testWidgets('submits by itself once the last digit lands', (tester) async {
      final submitted = <String>[];
      await tester.pumpWidget(
        _host(
          PasscodeEntryView(
            mode: PasscodeMode.digits4,
            title: 'Enter passcode',
            onSubmit: (code) async => submitted.add(code),
          ),
        ),
      );

      await _tapDigits(tester, '123');
      expect(submitted, isEmpty, reason: 'incomplete code must not submit');

      await _tapDigits(tester, '4');
      await tester.pumpAndSettle();

      expect(submitted, ['1234']);
    });

    testWidgets('backspace removes the last digit only', (tester) async {
      final submitted = <String>[];
      await tester.pumpWidget(
        _host(
          PasscodeEntryView(
            mode: PasscodeMode.digits4,
            title: 'Enter passcode',
            onSubmit: (code) async => submitted.add(code),
          ),
        ),
      );

      await _tapDigits(tester, '123');
      await tester.tap(find.byKey(const Key('passcode-backspace')));
      await tester.pump();

      expect(find.byKey(const Key('passcode-dot-filled-1')), findsOneWidget);
      expect(find.byKey(const Key('passcode-dot-empty-2')), findsOneWidget);

      await _tapDigits(tester, '34');
      await tester.pumpAndSettle();
      expect(submitted, ['1234']);
    });

    testWidgets('clears itself after a submit so a retry starts empty',
        (tester) async {
      await tester.pumpWidget(
        _host(
          PasscodeEntryView(
            mode: PasscodeMode.digits4,
            title: 'Enter passcode',
            onSubmit: (_) async {},
          ),
        ),
      );

      await _tapDigits(tester, '1234');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('passcode-dot-empty-0')), findsOneWidget);
      expect(find.byKey(const Key('passcode-dot-filled-0')), findsNothing);
    });

    testWidgets('a disabled view ignores taps (cooldown active)',
        (tester) async {
      final submitted = <String>[];
      await tester.pumpWidget(
        _host(
          PasscodeEntryView(
            mode: PasscodeMode.digits4,
            title: 'Enter passcode',
            enabled: false,
            onSubmit: (code) async => submitted.add(code),
          ),
        ),
      );

      await _tapDigits(tester, '1234');
      await tester.pumpAndSettle();

      expect(submitted, isEmpty);
      expect(find.byKey(const Key('passcode-dot-filled-0')), findsNothing);
    });

    testWidgets('shows the error text it is given', (tester) async {
      await tester.pumpWidget(
        _host(
          PasscodeEntryView(
            mode: PasscodeMode.digits4,
            title: 'Enter passcode',
            errorText: 'Wrong passcode',
            onSubmit: (_) async {},
          ),
        ),
      );

      expect(find.text('Wrong passcode'), findsOneWidget);
    });
  });

  group('PasscodeEntryView alphanumeric', () {
    testWidgets('uses a text field and an explicit submit, not the keypad',
        (tester) async {
      final submitted = <String>[];
      await tester.pumpWidget(
        _host(
          PasscodeEntryView(
            mode: PasscodeMode.alphanumeric,
            title: 'Enter passcode',
            onSubmit: (code) async => submitted.add(code),
          ),
        ),
      );

      expect(find.byKey(const Key('passcode-key-1')), findsNothing);
      expect(find.byKey(const Key('passcode-text-field')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('passcode-text-field')),
        'correct horse',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('passcode-submit')));
      await tester.pumpAndSettle();

      expect(submitted, ['correct horse']);
    });

    testWidgets('refuses a too-short custom passcode without submitting',
        (tester) async {
      final submitted = <String>[];
      await tester.pumpWidget(
        _host(
          PasscodeEntryView(
            mode: PasscodeMode.alphanumeric,
            title: 'Enter passcode',
            onSubmit: (code) async => submitted.add(code),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('passcode-text-field')),
        'ab',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('passcode-submit')));
      await tester.pumpAndSettle();

      expect(submitted, isEmpty);
    });
  });

  group('PasscodeEntryView options link', () {
    testWidgets('is absent unless a handler is supplied', (tester) async {
      await tester.pumpWidget(
        _host(
          PasscodeEntryView(
            mode: PasscodeMode.digits6,
            title: 'Enter passcode',
            onSubmit: (_) async {},
          ),
        ),
      );

      expect(find.byKey(const Key('passcode-options-link')), findsNothing);
    });

    testWidgets('calls the handler when tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          PasscodeEntryView(
            mode: PasscodeMode.digits6,
            title: 'Enter passcode',
            onSubmit: (_) async {},
            onOptions: () => taps++,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('passcode-options-link')));
      await tester.pump();

      expect(taps, 1);
    });
  });
}
