import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/user_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:fireplace/screens/edit_about_screen.dart';
import 'package:fireplace/screens/user_card_screen.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AuthProvider fake: applies profile mutations in memory so the card's
/// live-data path (self cards watch the provider) can be exercised without
/// network. The rework's contract under test: actions apply IN PLACE and the
/// card never pops itself.
class _FakeAuthProvider extends AuthProvider {
  UserModel? _user;

  _FakeAuthProvider(this._user);

  @override
  UserModel? get currentUser => _user;

  @override
  Future<void> updateProfileAbout(String? about) async {
    _user = _user!.copyWith(about: about, clearAbout: about == null);
    notifyListeners();
  }

  @override
  Future<void> deleteProfilePhoto(int photoId) async {
    final photos = _user!.profilePhotos
        .where((photo) => photo.id != photoId)
        .toList(growable: false);
    final primary = photos.where((photo) => photo.isPrimary).firstOrNull;
    _user = _user!.copyWith(
      profilePhotos: photos,
      profilePictureUrl: primary?.url,
      clearProfilePicture: primary == null,
    );
    notifyListeners();
  }

  @override
  Future<void> setPrimaryProfilePhoto(int photoId) async {
    final photos = [
      for (final photo in _user!.profilePhotos)
        UserProfilePhoto(
          id: photo.id,
          url: photo.url,
          isPrimary: photo.id == photoId,
          createdAt: photo.createdAt,
        ),
    ]..sort((a, b) => a.isPrimary == b.isPrimary ? 0 : (a.isPrimary ? -1 : 1));
    _user = _user!.copyWith(
      profilePhotos: photos,
      profilePictureUrl: photos.first.url,
    );
    notifyListeners();
  }
}

Widget _wrap(UserCardVisualData data, {AuthProvider? auth}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => auth ?? _FakeAuthProvider(null),
      ),
      ChangeNotifierProvider(create: (_) => FriendsProvider()),
    ],
    child: MaterialApp(
      theme: RpgTheme.themeDataLight,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: UserCardScreen(data: data, onMessage: () {}),
    ),
  );
}

UserModel _selfUser({String? about, int photoCount = 3}) {
  return UserModel.fromJson({
    'id': 1,
    'username': 'ember',
    'tag': '7004',
    'about': about,
    'profilePhotos': [
      for (var i = 0; i < photoCount; i++)
        {
          'id': i + 1,
          'url': 'https://example.test/photo${i + 1}.jpg',
          'isPrimary': i == 0,
          'createdAt': '2026-07-0${i + 1}T00:00:00.000Z',
        },
    ],
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const contact = UserCardVisualData(
    userId: 2,
    username: 'alice',
    tag: '0042',
    isSelf: false,
    hasConversation: false,
  );

  testWidgets('requires confirmation before removing or blocking a contact', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(contact));

    await tester.tap(find.text('Remove contact'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Friend?'), findsOneWidget);
    expect(
      find.text(
        'Remove alice from your contacts? This will delete all conversation history.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Friend?'), findsNothing);

    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    expect(find.text('Block alice#0042?'), findsOneWidget);
    expect(
      find.text('You will no longer be able to message this contact.'),
      findsOneWidget,
    );
  });

  group('photo gallery pager', () {
    testWidgets('swipe cycles all photos and the segment indicator follows', (
      tester,
    ) async {
      final auth = _FakeAuthProvider(_selfUser());
      await tester.pumpWidget(
        _wrap(
          UserCardVisualData.fromUser(
            auth.currentUser!,
            isSelf: true,
            hasConversation: false,
          ),
          auth: auth,
        ),
      );
      await tester.pump();

      final pageView = find.byType(PageView);
      expect(pageView, findsOneWidget);

      PageController controllerOf(Finder finder) =>
          (tester.widget<PageView>(finder)).controller!;
      expect(controllerOf(pageView).page, 0);

      // The pre-rework bug: the hero scrim absorbed pointers and swiping did
      // nothing. Drag ON the photo area must page.
      await tester.drag(pageView, const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(controllerOf(pageView).page, 1);

      await tester.drag(pageView, const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(controllerOf(pageView).page, 2);

      // No fourth page.
      await tester.drag(pageView, const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(controllerOf(pageView).page, 2);
    });
  });

  group('self card stays in place (nav-bounce regression)', () {
    testWidgets('saving About returns to the card and applies live', (
      tester,
    ) async {
      final auth = _FakeAuthProvider(_selfUser(about: 'old about'));
      await tester.pumpWidget(
        _wrap(
          UserCardVisualData.fromUser(
            auth.currentUser!,
            isSelf: true,
            hasConversation: false,
          ),
          auth: auth,
        ),
      );
      await tester.pump();

      await tester.dragFrom(
        tester.getCenter(find.byType(CustomScrollView)),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit About'));
      await tester.pumpAndSettle();
      expect(find.byType(EditAboutScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'new about');
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      // ONE pop back to the card — never past it to the shell.
      expect(find.byType(EditAboutScreen), findsNothing);
      expect(find.byType(UserCardScreen), findsOneWidget);
      expect(find.text('new about'), findsOneWidget);
    });

    testWidgets(
      'deleting the viewed photo keeps the card open and shows the next photo',
      (tester) async {
        final auth = _FakeAuthProvider(_selfUser(photoCount: 2));
        await tester.pumpWidget(
          _wrap(
            UserCardVisualData.fromUser(
              auth.currentUser!,
              isSelf: true,
              hasConversation: false,
            ),
            auth: auth,
          ),
        );
        await tester.pump();

        // View photo 2, then delete it through the manage sheet.
        await tester.drag(find.byType(PageView), const Offset(-600, 0));
        await tester.pumpAndSettle();

        await tester.dragFrom(
          tester.getCenter(find.byType(CustomScrollView)),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Manage photos'));
        await tester.pumpAndSettle();
        expect(find.text('PHOTO 2 OF 2'), findsOneWidget);

        await tester.tap(find.text('Delete this photo'));
        await tester.pumpAndSettle();
        expect(find.text('Delete photo?'), findsOneWidget);
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        // Card stays; pager clamps back to the surviving photo.
        expect(find.byType(UserCardScreen), findsOneWidget);
        final pageView = tester.widget<PageView>(find.byType(PageView));
        expect(pageView.controller!.page, 0);
        expect(find.text('1/3'), findsOneWidget); // add-photo counter updated
      },
    );

    testWidgets('set as main keeps the card open and reorders to page 1', (
      tester,
    ) async {
      final auth = _FakeAuthProvider(_selfUser(photoCount: 3));
      await tester.pumpWidget(
        _wrap(
          UserCardVisualData.fromUser(
            auth.currentUser!,
            isSelf: true,
            hasConversation: false,
          ),
          auth: auth,
        ),
      );
      await tester.pump();

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();

      await tester.dragFrom(
        tester.getCenter(find.byType(CustomScrollView)),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage photos'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set as main photo'));
      await tester.pumpAndSettle();

      expect(find.byType(UserCardScreen), findsOneWidget);
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.controller!.page, 0);
    });
  });

  testWidgets('requires confirmation before deleting a profile photo', (
    tester,
  ) async {
    final auth = _FakeAuthProvider(_selfUser(photoCount: 1));
    await tester.pumpWidget(
      _wrap(
        UserCardVisualData.fromUser(
          auth.currentUser!,
          isSelf: true,
          hasConversation: false,
        ),
        auth: auth,
      ),
    );
    await tester.pump();

    await tester.dragFrom(
      tester.getCenter(find.byType(CustomScrollView)),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage photos'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete this photo'));
    await tester.pumpAndSettle();

    expect(find.text('Delete photo?'), findsOneWidget);
    expect(
      find.text('This permanently deletes this profile photo.'),
      findsOneWidget,
    );
  });
}
