import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pl'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In pl, this message translates to:
  /// **'Fireplace'**
  String get appTitle;

  /// No description provided for @settings.
  ///
  /// In pl, this message translates to:
  /// **'Ustawienia'**
  String get settings;

  /// No description provided for @theme.
  ///
  /// In pl, this message translates to:
  /// **'Motyw'**
  String get theme;

  /// No description provided for @language.
  ///
  /// In pl, this message translates to:
  /// **'Język'**
  String get language;

  /// No description provided for @languagePolish.
  ///
  /// In pl, this message translates to:
  /// **'Polski'**
  String get languagePolish;

  /// No description provided for @languageEnglish.
  ///
  /// In pl, this message translates to:
  /// **'Angielski'**
  String get languageEnglish;

  /// No description provided for @privacyAndSafety.
  ///
  /// In pl, this message translates to:
  /// **'Prywatność i bezpieczeństwo'**
  String get privacyAndSafety;

  /// No description provided for @blocked.
  ///
  /// In pl, this message translates to:
  /// **'Zablokowani'**
  String get blocked;

  /// No description provided for @devices.
  ///
  /// In pl, this message translates to:
  /// **'Urządzenia'**
  String get devices;

  /// No description provided for @webPushEnableTitle.
  ///
  /// In pl, this message translates to:
  /// **'Włącz powiadomienia push'**
  String get webPushEnableTitle;

  /// No description provided for @webPushEnableSubtitle.
  ///
  /// In pl, this message translates to:
  /// **'Na iOS wymagane po dodaniu aplikacji do ekranu głównego'**
  String get webPushEnableSubtitle;

  /// No description provided for @webPushEnabled.
  ///
  /// In pl, this message translates to:
  /// **'Powiadomienia push włączone'**
  String get webPushEnabled;

  /// No description provided for @webPushPermissionDenied.
  ///
  /// In pl, this message translates to:
  /// **'Odrzucono uprawnienie do powiadomień'**
  String get webPushPermissionDenied;

  /// No description provided for @webPushInstallRequired.
  ///
  /// In pl, this message translates to:
  /// **'Najpierw dodaj Fireplace do ekranu głównego (Safari -> Udostępnij -> Do ekranu początkowego)'**
  String get webPushInstallRequired;

  /// No description provided for @webPushNotSupported.
  ///
  /// In pl, this message translates to:
  /// **'Powiadomienia push nie są obsługiwane w tej przeglądarce/sesji'**
  String get webPushNotSupported;

  /// No description provided for @webPushNoChanges.
  ///
  /// In pl, this message translates to:
  /// **'Powiadomienia push są już włączone'**
  String get webPushNoChanges;

  /// No description provided for @webPushEnableFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się włączyć powiadomień push'**
  String get webPushEnableFailed;

  /// No description provided for @resetPassword.
  ///
  /// In pl, this message translates to:
  /// **'Zmień hasło'**
  String get resetPassword;

  /// No description provided for @deleteAccount.
  ///
  /// In pl, this message translates to:
  /// **'Usuń konto'**
  String get deleteAccount;

  /// No description provided for @logout.
  ///
  /// In pl, this message translates to:
  /// **'Wyloguj'**
  String get logout;

  /// No description provided for @uninstallWarning.
  ///
  /// In pl, this message translates to:
  /// **'Odinstalowanie aplikacji lub wyczyszczenie danych witryny trwale usuwa historię wiadomości — aby odświeżyć, po prostu całkowicie zamknij i otwórz aplikację ponownie.'**
  String get uninstallWarning;

  /// No description provided for @chat.
  ///
  /// In pl, this message translates to:
  /// **'Czat'**
  String get chat;

  /// No description provided for @contacts.
  ///
  /// In pl, this message translates to:
  /// **'Kontakty'**
  String get contacts;

  /// No description provided for @profilePictureUpdated.
  ///
  /// In pl, this message translates to:
  /// **'Zdjęcie profilowe zaktualizowane'**
  String get profilePictureUpdated;

  /// No description provided for @uploadFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się przesłać'**
  String get uploadFailed;

  /// No description provided for @passwordUpdatedSuccessfully.
  ///
  /// In pl, this message translates to:
  /// **'Hasło zostało zmienione'**
  String get passwordUpdatedSuccessfully;

  /// No description provided for @passwordResetFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się zmienić hasła'**
  String get passwordResetFailed;

  /// No description provided for @accountDeletionFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się usunąć konta'**
  String get accountDeletionFailed;

  /// No description provided for @loading.
  ///
  /// In pl, this message translates to:
  /// **'Ładowanie…'**
  String get loading;

  /// No description provided for @devicesLoading.
  ///
  /// In pl, this message translates to:
  /// **'Ładowanie…'**
  String get devicesLoading;

  /// No description provided for @settingsAppVersion.
  ///
  /// In pl, this message translates to:
  /// **'Wersja aplikacji'**
  String get settingsAppVersion;

  /// No description provided for @privacySafetyTitle.
  ///
  /// In pl, this message translates to:
  /// **'Prywatność i bezpieczeństwo'**
  String get privacySafetyTitle;

  /// No description provided for @e2eEncryptionEnabled.
  ///
  /// In pl, this message translates to:
  /// **'Szyfrowanie end-to-end jest włączone'**
  String get e2eEncryptionEnabled;

  /// No description provided for @e2eEncryptionDescription.
  ///
  /// In pl, this message translates to:
  /// **'Twoje wiadomości są szyfrowane protokołem Signal. Tylko Ty i odbiorca możecie je odczytać. Serwery Fireplace nie mają dostępu do treści wiadomości.'**
  String get e2eEncryptionDescription;

  /// No description provided for @yourEncryptionKeys.
  ///
  /// In pl, this message translates to:
  /// **'Twoje klucze szyfrowania'**
  String get yourEncryptionKeys;

  /// No description provided for @yourEncryptionKeysDescription.
  ///
  /// In pl, this message translates to:
  /// **'Klucze są bezpiecznie przechowywane na tym urządzeniu. Po zmianie urządzenia lub reinstalacji aplikacji zostaną wygenerowane nowe klucze, a poprzedniej historii nie da się odzyskać.'**
  String get yourEncryptionKeysDescription;

  /// No description provided for @singleDeviceEncryption.
  ///
  /// In pl, this message translates to:
  /// **'Szyfrowanie na jednym urządzeniu'**
  String get singleDeviceEncryption;

  /// No description provided for @singleDeviceEncryptionDescription.
  ///
  /// In pl, this message translates to:
  /// **'Każde urządzenie ma własne klucze. Wiadomości są powiązane z urządzeniem, które je wysłało lub odebrało.'**
  String get singleDeviceEncryptionDescription;

  /// No description provided for @webKeyStorage.
  ///
  /// In pl, this message translates to:
  /// **'Przeglądarka: przechowywanie kluczy'**
  String get webKeyStorage;

  /// No description provided for @webKeyStorageDescription.
  ///
  /// In pl, this message translates to:
  /// **'W wersji web klucze są przechowywane w przeglądarce (szyfrowane WebCrypto). Osoba z dostępem do tego urządzenia mogłaby je odczytać. Dla maksymalnego bezpieczeństwa używaj aplikacji mobilnej.'**
  String get webKeyStorageDescription;

  /// No description provided for @whatIsEncrypted.
  ///
  /// In pl, this message translates to:
  /// **'Co jest szyfrowane'**
  String get whatIsEncrypted;

  /// No description provided for @whatIsEncryptedDescription.
  ///
  /// In pl, this message translates to:
  /// **'Wszystkie wiadomości są szyfrowane end-to-end (tekst, zdjęcia, głos, linki). Tylko Ty i odbiorca możecie je odczytać.'**
  String get whatIsEncryptedDescription;

  /// No description provided for @serverStoresMetadata.
  ///
  /// In pl, this message translates to:
  /// **'Co przechowuje serwer (metadane)'**
  String get serverStoresMetadata;

  /// No description provided for @serverStoresMetadataDescription.
  ///
  /// In pl, this message translates to:
  /// **'Aby dostarczać wiadomości, serwer przechowuje: kto jest w danej rozmowie, kiedy wiadomości zostały wysłane oraz status dostarczenia. Treść wiadomości nigdy nie jest widoczna dla serwera.'**
  String get serverStoresMetadataDescription;

  /// No description provided for @localMessageCache.
  ///
  /// In pl, this message translates to:
  /// **'Lokalna pamięć wiadomości'**
  String get localMessageCache;

  /// No description provided for @localMessageCacheDescription.
  ///
  /// In pl, this message translates to:
  /// **'Dla niezawodności to urządzenie może lokalnie przechowywać odszyfrowane podglądy wiadomości i pobrane wiadomości głosowe. Wyczyszczenie tej pamięci nie usuwa kluczy szyfrowania ani historii z serwera.'**
  String get localMessageCacheDescription;

  /// No description provided for @clearLocalMessageCache.
  ///
  /// In pl, this message translates to:
  /// **'Wyczyść lokalną pamięć wiadomości'**
  String get clearLocalMessageCache;

  /// No description provided for @yourIdentityFingerprint.
  ///
  /// In pl, this message translates to:
  /// **'Twój odcisk tożsamości'**
  String get yourIdentityFingerprint;

  /// No description provided for @shareFingerprintHint.
  ///
  /// In pl, this message translates to:
  /// **'To unikalna reprezentacja Twojego klucza szyfrowania.'**
  String get shareFingerprintHint;

  /// No description provided for @addInvitations.
  ///
  /// In pl, this message translates to:
  /// **'Dodaj / Zaproszenia'**
  String get addInvitations;

  /// No description provided for @addUser.
  ///
  /// In pl, this message translates to:
  /// **'Dodaj użytkownika'**
  String get addUser;

  /// No description provided for @friendRequests.
  ///
  /// In pl, this message translates to:
  /// **'Zaproszenia'**
  String get friendRequests;

  /// No description provided for @friendRequestSentTo.
  ///
  /// In pl, this message translates to:
  /// **'Zaproszenie wysłane do {handle}'**
  String friendRequestSentTo(String handle);

  /// No description provided for @addNewUserHint.
  ///
  /// In pl, this message translates to:
  /// **'Dodaj użytkownika po username#tag (np. username#1234). Swój #tag znajdziesz w Ustawieniach przy nicku. Każdy #tag jest unikalny.'**
  String get addNewUserHint;

  /// No description provided for @usernameTagPlaceholder.
  ///
  /// In pl, this message translates to:
  /// **'username#1234'**
  String get usernameTagPlaceholder;

  /// No description provided for @addNewUser.
  ///
  /// In pl, this message translates to:
  /// **'Dodaj użytkownika'**
  String get addNewUser;

  /// No description provided for @userNotFound.
  ///
  /// In pl, this message translates to:
  /// **'Nie znaleziono użytkownika'**
  String get userNotFound;

  /// No description provided for @noPendingRequests.
  ///
  /// In pl, this message translates to:
  /// **'Brak oczekujących zaproszeń'**
  String get noPendingRequests;

  /// No description provided for @wantsToAddYouAsFriend.
  ///
  /// In pl, this message translates to:
  /// **'chce dodać Cię do znajomych'**
  String get wantsToAddYouAsFriend;

  /// No description provided for @accept.
  ///
  /// In pl, this message translates to:
  /// **'Zaakceptuj'**
  String get accept;

  /// No description provided for @reject.
  ///
  /// In pl, this message translates to:
  /// **'Odrzuć'**
  String get reject;

  /// No description provided for @friendAdded.
  ///
  /// In pl, this message translates to:
  /// **'Dodano do znajomych: {name}'**
  String friendAdded(String name);

  /// No description provided for @requestRejected.
  ///
  /// In pl, this message translates to:
  /// **'Zaproszenie odrzucone'**
  String get requestRejected;

  /// No description provided for @encryptedMessage.
  ///
  /// In pl, this message translates to:
  /// **'Wiadomość zaszyfrowana'**
  String get encryptedMessage;

  /// No description provided for @decryptionFailed.
  ///
  /// In pl, this message translates to:
  /// **'Odszyfrowanie nie powiodło się'**
  String get decryptionFailed;

  /// No description provided for @encryptionNotInitialized.
  ///
  /// In pl, this message translates to:
  /// **'Szyfrowanie niezainicjowane'**
  String get encryptionNotInitialized;

  /// No description provided for @blockUser.
  ///
  /// In pl, this message translates to:
  /// **'Zablokuj użytkownika'**
  String get blockUser;

  /// No description provided for @conversationDeletedByOther.
  ///
  /// In pl, this message translates to:
  /// **'Rozmowa usunięta przez drugą osobę'**
  String get conversationDeletedByOther;

  /// No description provided for @noMessagesYet.
  ///
  /// In pl, this message translates to:
  /// **'Brak wiadomości'**
  String get noMessagesYet;

  /// No description provided for @cantMessageThisUser.
  ///
  /// In pl, this message translates to:
  /// **'Nie możesz pisać do tego użytkownika'**
  String get cantMessageThisUser;

  /// No description provided for @cantTypeToThisUser.
  ///
  /// In pl, this message translates to:
  /// **'Nie możesz pisać do tego użytkownika'**
  String get cantTypeToThisUser;

  /// No description provided for @recordingVoice.
  ///
  /// In pl, this message translates to:
  /// **'Nagrywanie głosu…'**
  String get recordingVoice;

  /// No description provided for @typing.
  ///
  /// In pl, this message translates to:
  /// **'pisze…'**
  String get typing;

  /// No description provided for @chatMessageHint.
  ///
  /// In pl, this message translates to:
  /// **'Napisz wiadomość…'**
  String get chatMessageHint;

  /// No description provided for @chatComposerSendTooltip.
  ///
  /// In pl, this message translates to:
  /// **'Wyślij'**
  String get chatComposerSendTooltip;

  /// No description provided for @chatComposerSendSemantics.
  ///
  /// In pl, this message translates to:
  /// **'Wyślij wiadomość'**
  String get chatComposerSendSemantics;

  /// No description provided for @chatComposerEmojiTooltip.
  ///
  /// In pl, this message translates to:
  /// **'Emoji'**
  String get chatComposerEmojiTooltip;

  /// No description provided for @chatComposerEmojiSemantics.
  ///
  /// In pl, this message translates to:
  /// **'Otwórz panel emoji'**
  String get chatComposerEmojiSemantics;

  /// No description provided for @emojiPickerSemantics.
  ///
  /// In pl, this message translates to:
  /// **'Panel emoji'**
  String get emojiPickerSemantics;

  /// No description provided for @emojiPickerSearchHint.
  ///
  /// In pl, this message translates to:
  /// **'Szukaj emoji'**
  String get emojiPickerSearchHint;

  /// No description provided for @emojiPickerNoRecents.
  ///
  /// In pl, this message translates to:
  /// **'Brak ostatnich emoji'**
  String get emojiPickerNoRecents;

  /// No description provided for @emojiPickerEmojiOptionSemantics.
  ///
  /// In pl, this message translates to:
  /// **'Emoji {emoji}'**
  String emojiPickerEmojiOptionSemantics(String emoji);

  /// No description provided for @chatDateToday.
  ///
  /// In pl, this message translates to:
  /// **'Dziś'**
  String get chatDateToday;

  /// No description provided for @chatDateYesterday.
  ///
  /// In pl, this message translates to:
  /// **'Wczoraj'**
  String get chatDateYesterday;

  /// No description provided for @selectAConversation.
  ///
  /// In pl, this message translates to:
  /// **'Wybierz rozmowę'**
  String get selectAConversation;

  /// No description provided for @noConversationsYet.
  ///
  /// In pl, this message translates to:
  /// **'Brak czatów'**
  String get noConversationsYet;

  /// No description provided for @startNewChatToBegin.
  ///
  /// In pl, this message translates to:
  /// **'Rozpocznij czat, aby zacząć'**
  String get startNewChatToBegin;

  /// No description provided for @deleteConversationTitle.
  ///
  /// In pl, this message translates to:
  /// **'Usuń rozmowę?'**
  String get deleteConversationTitle;

  /// No description provided for @deleteConversationConfirm.
  ///
  /// In pl, this message translates to:
  /// **'Wszystkie wiadomości z tej rozmowy zostaną usunięte. Później możesz otworzyć czat z Kontaktów.'**
  String get deleteConversationConfirm;

  /// No description provided for @cancel.
  ///
  /// In pl, this message translates to:
  /// **'Anuluj'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In pl, this message translates to:
  /// **'Usuń'**
  String get delete;

  /// No description provided for @voiceMessage.
  ///
  /// In pl, this message translates to:
  /// **'Wiadomość głosowa'**
  String get voiceMessage;

  /// No description provided for @image.
  ///
  /// In pl, this message translates to:
  /// **'Obraz'**
  String get image;

  /// No description provided for @ping.
  ///
  /// In pl, this message translates to:
  /// **'Ping'**
  String get ping;

  /// No description provided for @attachment.
  ///
  /// In pl, this message translates to:
  /// **'Załącznik'**
  String get attachment;

  /// No description provided for @attachmentOptionPhoto.
  ///
  /// In pl, this message translates to:
  /// **'Zdjęcie'**
  String get attachmentOptionPhoto;

  /// No description provided for @attachmentOptionDocument.
  ///
  /// In pl, this message translates to:
  /// **'Dokument'**
  String get attachmentOptionDocument;

  /// No description provided for @actionTileTimer.
  ///
  /// In pl, this message translates to:
  /// **'Timer'**
  String get actionTileTimer;

  /// No description provided for @actionTileDisappearingMessages.
  ///
  /// In pl, this message translates to:
  /// **'Znikające wiadomości'**
  String get actionTileDisappearingMessages;

  /// No description provided for @disappearingTimerTitle.
  ///
  /// In pl, this message translates to:
  /// **'Znikające wiadomości'**
  String get disappearingTimerTitle;

  /// No description provided for @disappearingTimerExplainerLine1.
  ///
  /// In pl, this message translates to:
  /// **'Wiadomości znikają po odczytaniu.'**
  String get disappearingTimerExplainerLine1;

  /// No description provided for @disappearingTimerExplainerLine2.
  ///
  /// In pl, this message translates to:
  /// **'Odliczanie startuje, gdy ktoś otworzy czat.'**
  String get disappearingTimerExplainerLine2;

  /// No description provided for @disappearingTimerExplainerLine3.
  ///
  /// In pl, this message translates to:
  /// **'Tylko nowe wiadomości używają ustawionego tu czasu.'**
  String get disappearingTimerExplainerLine3;

  /// No description provided for @disappearingTimerRangeHint.
  ///
  /// In pl, this message translates to:
  /// **'Od 5 sekund do 30 dni; same zera = wyłączone'**
  String get disappearingTimerRangeHint;

  /// No description provided for @disappearingTimerSetTimer.
  ///
  /// In pl, this message translates to:
  /// **'Ustaw timer'**
  String get disappearingTimerSetTimer;

  /// No description provided for @disappearingTimerTurnOff.
  ///
  /// In pl, this message translates to:
  /// **'Wyłącz'**
  String get disappearingTimerTurnOff;

  /// No description provided for @disappearingTimerSummarySemantics.
  ///
  /// In pl, this message translates to:
  /// **'Wybrany czas: {summary}'**
  String disappearingTimerSummarySemantics(String summary);

  /// No description provided for @disappearingComposerBanner.
  ///
  /// In pl, this message translates to:
  /// **'Znikające · {duration}'**
  String disappearingComposerBanner(String duration);

  /// No description provided for @disappearingComposerBannerSemantics.
  ///
  /// In pl, this message translates to:
  /// **'Znikające wiadomości, {duration}'**
  String disappearingComposerBannerSemantics(String duration);

  /// No description provided for @conversationDisappearingTimerHint.
  ///
  /// In pl, this message translates to:
  /// **'Znikające wiadomości: {duration}'**
  String conversationDisappearingTimerHint(String duration);

  /// No description provided for @conversationLastMessageEphemeralPreRead.
  ///
  /// In pl, this message translates to:
  /// **'Znika po odczytaniu'**
  String get conversationLastMessageEphemeralPreRead;

  /// No description provided for @conversationLastMessageEphemeralRemaining.
  ///
  /// In pl, this message translates to:
  /// **'Znika za {duration}'**
  String conversationLastMessageEphemeralRemaining(String duration);

  /// No description provided for @disappearingTimerDaysLabel.
  ///
  /// In pl, this message translates to:
  /// **'Dni'**
  String get disappearingTimerDaysLabel;

  /// No description provided for @disappearingTimerHoursLabel.
  ///
  /// In pl, this message translates to:
  /// **'Godziny'**
  String get disappearingTimerHoursLabel;

  /// No description provided for @disappearingTimerMinutesLabel.
  ///
  /// In pl, this message translates to:
  /// **'Minuty'**
  String get disappearingTimerMinutesLabel;

  /// No description provided for @disappearingTimerSecondsLabel.
  ///
  /// In pl, this message translates to:
  /// **'Sekundy'**
  String get disappearingTimerSecondsLabel;

  /// No description provided for @disappearingTimerApply.
  ///
  /// In pl, this message translates to:
  /// **'Zastosuj'**
  String get disappearingTimerApply;

  /// No description provided for @disappearingTimerOff.
  ///
  /// In pl, this message translates to:
  /// **'Wyłączone'**
  String get disappearingTimerOff;

  /// No description provided for @disappearingTimerOutOfRange.
  ///
  /// In pl, this message translates to:
  /// **'Timer: od 5 sekund do 30 dni albo same zera, aby wyłączyć.'**
  String get disappearingTimerOutOfRange;

  /// No description provided for @disappearingTimerDays.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{1 dzień} few{{count} dni} many{{count} dni} other{{count} dnia}}'**
  String disappearingTimerDays(num count);

  /// No description provided for @disappearingTimerHours.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{1 godzina} few{{count} godziny} many{{count} godzin} other{{count} godziny}}'**
  String disappearingTimerHours(num count);

  /// No description provided for @disappearingTimerMinutes.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{1 minuta} few{{count} minuty} many{{count} minut} other{{count} minuty}}'**
  String disappearingTimerMinutes(num count);

  /// No description provided for @disappearingTimerSeconds.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, one{1 sekunda} few{{count} sekundy} many{{count} sekund} other{{count} sekundy}}'**
  String disappearingTimerSeconds(num count);

  /// No description provided for @actionTileGif.
  ///
  /// In pl, this message translates to:
  /// **'GIF'**
  String get actionTileGif;

  /// No description provided for @actionTileAntiQuantumNote.
  ///
  /// In pl, this message translates to:
  /// **'Notatka antykwantowa'**
  String get actionTileAntiQuantumNote;

  /// No description provided for @unknown.
  ///
  /// In pl, this message translates to:
  /// **'Nieznany'**
  String get unknown;

  /// No description provided for @noBlockedUsers.
  ///
  /// In pl, this message translates to:
  /// **'Brak zablokowanych użytkowników'**
  String get noBlockedUsers;

  /// No description provided for @unblock.
  ///
  /// In pl, this message translates to:
  /// **'Odblokuj'**
  String get unblock;

  /// No description provided for @removeFriendTitle.
  ///
  /// In pl, this message translates to:
  /// **'Usuń z kontaktów?'**
  String get removeFriendTitle;

  /// No description provided for @removeFriendConfirm.
  ///
  /// In pl, this message translates to:
  /// **'Usunąć {name} z kontaktów? Zostanie usunięta cała historia rozmowy.'**
  String removeFriendConfirm(String name);

  /// No description provided for @remove.
  ///
  /// In pl, this message translates to:
  /// **'Usuń'**
  String get remove;

  /// No description provided for @noContactsYet.
  ///
  /// In pl, this message translates to:
  /// **'Brak kontaktów'**
  String get noContactsYet;

  /// No description provided for @addFriendsToStart.
  ///
  /// In pl, this message translates to:
  /// **'Dodaj znajomych, aby zacząć pisać'**
  String get addFriendsToStart;

  /// No description provided for @block.
  ///
  /// In pl, this message translates to:
  /// **'Zablokuj'**
  String get block;

  /// No description provided for @imageFailedToLoad.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się załadować obrazu'**
  String get imageFailedToLoad;

  /// No description provided for @unsupportedMessageType.
  ///
  /// In pl, this message translates to:
  /// **'Nieobsługiwany typ wiadomości'**
  String get unsupportedMessageType;

  /// No description provided for @resetPasswordDialogTitle.
  ///
  /// In pl, this message translates to:
  /// **'Zmień hasło'**
  String get resetPasswordDialogTitle;

  /// No description provided for @oldPassword.
  ///
  /// In pl, this message translates to:
  /// **'Obecne hasło'**
  String get oldPassword;

  /// No description provided for @newPassword.
  ///
  /// In pl, this message translates to:
  /// **'Nowe hasło'**
  String get newPassword;

  /// No description provided for @passwordRequired.
  ///
  /// In pl, this message translates to:
  /// **'Hasło jest wymagane'**
  String get passwordRequired;

  /// No description provided for @passwordMinLength.
  ///
  /// In pl, this message translates to:
  /// **'Hasło musi mieć co najmniej 8 znaków'**
  String get passwordMinLength;

  /// No description provided for @passwordMustContain.
  ///
  /// In pl, this message translates to:
  /// **'Hasło musi zawierać wielką literę, małą literę i cyfrę'**
  String get passwordMustContain;

  /// No description provided for @oldPasswordRequired.
  ///
  /// In pl, this message translates to:
  /// **'Obecne hasło jest wymagane'**
  String get oldPasswordRequired;

  /// No description provided for @resetButton.
  ///
  /// In pl, this message translates to:
  /// **'Zmień'**
  String get resetButton;

  /// No description provided for @deleteAccountDialogTitle.
  ///
  /// In pl, this message translates to:
  /// **'Usuń konto'**
  String get deleteAccountDialogTitle;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In pl, this message translates to:
  /// **'Ta operacja jest nieodwracalna. Wszystkie Twoje wiadomości i rozmowy zostaną usunięte.'**
  String get deleteAccountWarning;

  /// No description provided for @enterPasswordToConfirm.
  ///
  /// In pl, this message translates to:
  /// **'Wpisz hasło, aby potwierdzić'**
  String get enterPasswordToConfirm;

  /// No description provided for @clearingChat.
  ///
  /// In pl, this message translates to:
  /// **'Czyszczenie…'**
  String get clearingChat;

  /// No description provided for @gifNoResults.
  ///
  /// In pl, this message translates to:
  /// **'Nie znaleziono GIFów'**
  String get gifNoResults;

  /// No description provided for @gifSearchHint.
  ///
  /// In pl, this message translates to:
  /// **'Szukaj GIFów...'**
  String get gifSearchHint;

  /// No description provided for @gifLoadError.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się załadować GIFów'**
  String get gifLoadError;

  /// No description provided for @antiQuantumNoteTitle.
  ///
  /// In pl, this message translates to:
  /// **'Notatka antykwantowa'**
  String get antiQuantumNoteTitle;

  /// No description provided for @antiQuantumNoteHint.
  ///
  /// In pl, this message translates to:
  /// **'Napisz swoją tajną wiadomość...'**
  String get antiQuantumNoteHint;

  /// No description provided for @antiQuantumNoteTtl1h.
  ///
  /// In pl, this message translates to:
  /// **'1h'**
  String get antiQuantumNoteTtl1h;

  /// No description provided for @antiQuantumNoteTtl6h.
  ///
  /// In pl, this message translates to:
  /// **'6h'**
  String get antiQuantumNoteTtl6h;

  /// No description provided for @antiQuantumNoteTtl12h.
  ///
  /// In pl, this message translates to:
  /// **'12h'**
  String get antiQuantumNoteTtl12h;

  /// No description provided for @antiQuantumNoteTtl24h.
  ///
  /// In pl, this message translates to:
  /// **'24h'**
  String get antiQuantumNoteTtl24h;

  /// No description provided for @antiQuantumNoteGenerateAndSend.
  ///
  /// In pl, this message translates to:
  /// **'🔗 Wygeneruj i wyślij'**
  String get antiQuantumNoteGenerateAndSend;

  /// No description provided for @antiQuantumNoteFooter.
  ///
  /// In pl, this message translates to:
  /// **'Szyfrowanie po stronie klienta · Klucz nigdy nie opuszcza Twojego urządzenia'**
  String get antiQuantumNoteFooter;

  /// No description provided for @antiQuantumNoteSent.
  ///
  /// In pl, this message translates to:
  /// **'Notatka antykwantowa wysłana'**
  String get antiQuantumNoteSent;

  /// No description provided for @antiQuantumNoteSendFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się wysłać notatki: {error}'**
  String antiQuantumNoteSendFailed(String error);

  /// No description provided for @antiQuantumNoteCardSubtitle.
  ///
  /// In pl, this message translates to:
  /// **'Jednorazowy odczyt · Dotknij, aby otworzyć'**
  String get antiQuantumNoteCardSubtitle;

  /// No description provided for @antiQuantumNoteCardCountdown.
  ///
  /// In pl, this message translates to:
  /// **'Zniszczy się za {time}'**
  String antiQuantumNoteCardCountdown(String time);

  /// No description provided for @antiQuantumNoteCardDestroyed.
  ///
  /// In pl, this message translates to:
  /// **'Ta notatka uległa samozniszczeniu'**
  String get antiQuantumNoteCardDestroyed;

  /// No description provided for @privacyAntiQuantumNoteTitle.
  ///
  /// In pl, this message translates to:
  /// **'Notatki antykwantowe'**
  String get privacyAntiQuantumNoteTitle;

  /// No description provided for @privacyAntiQuantumNoteDescription.
  ///
  /// In pl, this message translates to:
  /// **'Notatki są szyfrowane na Twoim urządzeniu przed wysłaniem — serwer przechowuje wyłącznie nieczytelny szyfrogram, a klucz deszyfrujący podróżuje jedynie we fragmencie linku (#), którego przeglądarki nigdy nie wysyłają do żadnego serwera. Notatkę można odczytać dokładnie raz, po czym jest trwale usuwana. Nieotwarte notatki niszczą się same po upływie timera (1h–24h), a wiadomość w czacie znika razem z nimi.'**
  String get privacyAntiQuantumNoteDescription;

  /// No description provided for @documentDownloaded.
  ///
  /// In pl, this message translates to:
  /// **'Dokument pobrany'**
  String get documentDownloaded;

  /// No description provided for @documentDownloadFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się pobrać dokumentu'**
  String get documentDownloadFailed;

  /// No description provided for @documentDownloadConfirmTitle.
  ///
  /// In pl, this message translates to:
  /// **'Pobrać dokument?'**
  String get documentDownloadConfirmTitle;

  /// No description provided for @documentDownloadConfirmMessage.
  ///
  /// In pl, this message translates to:
  /// **'Czy chcesz pobrać ten plik?'**
  String get documentDownloadConfirmMessage;

  /// No description provided for @download.
  ///
  /// In pl, this message translates to:
  /// **'Pobierz'**
  String get download;

  /// No description provided for @snackbarCouldNotReadFile.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się odczytać pliku'**
  String get snackbarCouldNotReadFile;

  /// No description provided for @snackbarUploadingImage.
  ///
  /// In pl, this message translates to:
  /// **'Wysyłanie zdjęcia…'**
  String get snackbarUploadingImage;

  /// No description provided for @snackbarImageSent.
  ///
  /// In pl, this message translates to:
  /// **'Zdjęcie wysłane!'**
  String get snackbarImageSent;

  /// No description provided for @snackbarUploadingDocument.
  ///
  /// In pl, this message translates to:
  /// **'Wysyłanie dokumentu…'**
  String get snackbarUploadingDocument;

  /// No description provided for @snackbarDocumentSent.
  ///
  /// In pl, this message translates to:
  /// **'Dokument wysłany!'**
  String get snackbarDocumentSent;

  /// No description provided for @snackbarNoActiveConversation.
  ///
  /// In pl, this message translates to:
  /// **'Brak aktywnej rozmowy'**
  String get snackbarNoActiveConversation;

  /// No description provided for @snackbarOpenConversationFirst.
  ///
  /// In pl, this message translates to:
  /// **'Najpierw otwórz rozmowę'**
  String get snackbarOpenConversationFirst;

  /// No description provided for @snackbarChatHistoryDeleted.
  ///
  /// In pl, this message translates to:
  /// **'Historia czatu została usunięta'**
  String get snackbarChatHistoryDeleted;

  /// No description provided for @snackbarFailedToSendImage.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się wysłać zdjęcia'**
  String get snackbarFailedToSendImage;

  /// No description provided for @snackbarMicrophonePermissionRequired.
  ///
  /// In pl, this message translates to:
  /// **'Wymagane jest uprawnienie do mikrofonu'**
  String get snackbarMicrophonePermissionRequired;

  /// No description provided for @snackbarMicrophonePermissionDenied.
  ///
  /// In pl, this message translates to:
  /// **'Odmowa dostępu do mikrofonu'**
  String get snackbarMicrophonePermissionDenied;

  /// No description provided for @snackbarNoMicrophoneFound.
  ///
  /// In pl, this message translates to:
  /// **'Nie znaleziono mikrofonu'**
  String get snackbarNoMicrophoneFound;

  /// No description provided for @snackbarVoiceRecordingRequiresSecureContext.
  ///
  /// In pl, this message translates to:
  /// **'Nagrywanie głosu wymaga HTTPS lub localhost. Użyj https:// lub otwórz z localhost.'**
  String get snackbarVoiceRecordingRequiresSecureContext;

  /// No description provided for @snackbarFailedToStartRecording.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się rozpocząć nagrywania'**
  String get snackbarFailedToStartRecording;

  /// No description provided for @snackbarVoiceRecordingCanceled.
  ///
  /// In pl, this message translates to:
  /// **'Nagrywanie głosu anulowane'**
  String get snackbarVoiceRecordingCanceled;

  /// No description provided for @voiceRecordingSendVoiceTooltip.
  ///
  /// In pl, this message translates to:
  /// **'Wyślij wiadomość głosową'**
  String get voiceRecordingSendVoiceTooltip;

  /// No description provided for @voiceRecordingSendVoiceSemantics.
  ///
  /// In pl, this message translates to:
  /// **'Wyślij wiadomość głosową'**
  String get voiceRecordingSendVoiceSemantics;

  /// No description provided for @voiceRecordingDiscard.
  ///
  /// In pl, this message translates to:
  /// **'Odrzuć nagranie'**
  String get voiceRecordingDiscard;

  /// No description provided for @voiceRecordingSemanticsLabel.
  ///
  /// In pl, this message translates to:
  /// **'Nagrywanie wiadomości głosowej, {time}.'**
  String voiceRecordingSemanticsLabel(String time);

  /// No description provided for @snackbarFailedToReadRecording.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się odczytać nagrania'**
  String get snackbarFailedToReadRecording;

  /// No description provided for @snackbarFailedToSendVoiceMessage.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się wysłać wiadomości głosowej'**
  String get snackbarFailedToSendVoiceMessage;

  /// No description provided for @snackbarAudioNoLongerAvailable.
  ///
  /// In pl, this message translates to:
  /// **'Dźwięk nie jest już dostępny'**
  String get snackbarAudioNoLongerAvailable;

  /// No description provided for @snackbarFailedToLoadAudio.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się wczytać dźwięku'**
  String get snackbarFailedToLoadAudio;

  /// No description provided for @snackbarLocalMessageCacheCleared.
  ///
  /// In pl, this message translates to:
  /// **'Lokalna pamięć wiadomości wyczyszczona'**
  String get snackbarLocalMessageCacheCleared;

  /// No description provided for @snackbarFailedToClearLocalMessageCache.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się wyczyścić lokalnej pamięci wiadomości'**
  String get snackbarFailedToClearLocalMessageCache;

  /// No description provided for @friendAcceptedYourRequest.
  ///
  /// In pl, this message translates to:
  /// **'{name} zaakceptował(a) zaproszenie do znajomych'**
  String friendAcceptedYourRequest(String name);

  /// No description provided for @themeOptionLight.
  ///
  /// In pl, this message translates to:
  /// **'Ciepły papier (jasny)'**
  String get themeOptionLight;

  /// No description provided for @themeOptionDark.
  ///
  /// In pl, this message translates to:
  /// **'Ciemny szary z turkusowym akcentem'**
  String get themeOptionDark;

  /// No description provided for @themeOptionBlue.
  ///
  /// In pl, this message translates to:
  /// **'Niebieski w stylu Telegram (ciemny)'**
  String get themeOptionBlue;

  /// No description provided for @themeOptionTealStone.
  ///
  /// In pl, this message translates to:
  /// **'Turkus i kamień (nowoczesny jasny)'**
  String get themeOptionTealStone;

  /// No description provided for @rotateDeviceTitle.
  ///
  /// In pl, this message translates to:
  /// **'Obróć urządzenie'**
  String get rotateDeviceTitle;

  /// No description provided for @rotateDeviceMessage.
  ///
  /// In pl, this message translates to:
  /// **'Fireplace działa tylko w trybie pionowym.'**
  String get rotateDeviceMessage;

  /// No description provided for @messageActionReply.
  ///
  /// In pl, this message translates to:
  /// **'Odpowiedz'**
  String get messageActionReply;

  /// No description provided for @messageActionCopy.
  ///
  /// In pl, this message translates to:
  /// **'Kopiuj'**
  String get messageActionCopy;

  /// No description provided for @messageActionEdit.
  ///
  /// In pl, this message translates to:
  /// **'Edytuj'**
  String get messageActionEdit;

  /// No description provided for @messageActionPin.
  ///
  /// In pl, this message translates to:
  /// **'Przypnij'**
  String get messageActionPin;

  /// No description provided for @messageActionDelete.
  ///
  /// In pl, this message translates to:
  /// **'Usuń'**
  String get messageActionDelete;

  /// No description provided for @messageDeleteDialogTitle.
  ///
  /// In pl, this message translates to:
  /// **'Usunąć wiadomość?'**
  String get messageDeleteDialogTitle;

  /// No description provided for @messageDeleteForMe.
  ///
  /// In pl, this message translates to:
  /// **'Usuń u mnie'**
  String get messageDeleteForMe;

  /// No description provided for @messageDeleteForEveryone.
  ///
  /// In pl, this message translates to:
  /// **'Usuń dla wszystkich'**
  String get messageDeleteForEveryone;

  /// No description provided for @messageEditedLabel.
  ///
  /// In pl, this message translates to:
  /// **'edytowano'**
  String get messageEditedLabel;

  /// No description provided for @messageEditingTitle.
  ///
  /// In pl, this message translates to:
  /// **'Edytowanie wiadomości'**
  String get messageEditingTitle;

  /// No description provided for @messagePinRequiresSentMessage.
  ///
  /// In pl, this message translates to:
  /// **'Poczekaj na wysłanie wiadomości, aby ją przypiąć'**
  String get messagePinRequiresSentMessage;

  /// No description provided for @messageReactionMoreEmoji.
  ///
  /// In pl, this message translates to:
  /// **'Więcej reakcji emoji'**
  String get messageReactionMoreEmoji;

  /// No description provided for @messageReactionSelected.
  ///
  /// In pl, this message translates to:
  /// **'wybrana'**
  String get messageReactionSelected;

  /// No description provided for @messageReactionNotSelected.
  ///
  /// In pl, this message translates to:
  /// **'niewybrana'**
  String get messageReactionNotSelected;

  /// No description provided for @messageReactionSemantics.
  ///
  /// In pl, this message translates to:
  /// **'Reakcja {emoji}, {state}'**
  String messageReactionSemantics(Object emoji, Object state);

  /// No description provided for @snackbarPinnedMessageUnavailable.
  ///
  /// In pl, this message translates to:
  /// **'Wiadomość jest niedostępna'**
  String get snackbarPinnedMessageUnavailable;

  /// No description provided for @snackbarMessageCopied.
  ///
  /// In pl, this message translates to:
  /// **'Skopiowano wiadomość'**
  String get snackbarMessageCopied;

  /// No description provided for @composerAttachmentRemoveTooltip.
  ///
  /// In pl, this message translates to:
  /// **'Usuń załącznik'**
  String get composerAttachmentRemoveTooltip;

  /// No description provided for @snackbarPastedImageTooLarge.
  ///
  /// In pl, this message translates to:
  /// **'Obraz jest za duży (maks. 20 MB)'**
  String get snackbarPastedImageTooLarge;

  /// No description provided for @snackbarPastedImageUnsupported.
  ///
  /// In pl, this message translates to:
  /// **'Nie można wkleić tego typu obrazu'**
  String get snackbarPastedImageUnsupported;

  /// No description provided for @snackbarPastedImageUnavailable.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się odczytać wklejonego obrazu'**
  String get snackbarPastedImageUnavailable;

  /// No description provided for @pinnedMessageUnpinTooltip.
  ///
  /// In pl, this message translates to:
  /// **'Odepnij'**
  String get pinnedMessageUnpinTooltip;

  /// No description provided for @pinnedMessageBannerSemantics.
  ///
  /// In pl, this message translates to:
  /// **'Przypięta wiadomość'**
  String get pinnedMessageBannerSemantics;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pl':
      return AppLocalizationsPl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
