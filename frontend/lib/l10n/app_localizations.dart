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
  /// **'Czaty'**
  String get chat;

  /// No description provided for @contacts.
  ///
  /// In pl, this message translates to:
  /// **'Kontakty'**
  String get contacts;

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

  /// No description provided for @devicesLoading.
  ///
  /// In pl, this message translates to:
  /// **'Ładowanie…'**
  String get devicesLoading;

  /// No description provided for @devicesExplainer.
  ///
  /// In pl, this message translates to:
  /// **'Urządzenia połączone z tym kontem. Nowe urządzenie można dodać tylko z tego, głównego urządzenia.'**
  String get devicesExplainer;

  /// No description provided for @devicesNotEnrolled.
  ///
  /// In pl, this message translates to:
  /// **'Łączenie urządzeń nie jest jeszcze włączone dla tego konta.'**
  String get devicesNotEnrolled;

  /// No description provided for @devicesEnableLinking.
  ///
  /// In pl, this message translates to:
  /// **'Włącz łączenie'**
  String get devicesEnableLinking;

  /// No description provided for @devicesLinkADevice.
  ///
  /// In pl, this message translates to:
  /// **'Połącz urządzenie'**
  String get devicesLinkADevice;

  /// No description provided for @devicesLinkThisDevice.
  ///
  /// In pl, this message translates to:
  /// **'Połącz to urządzenie'**
  String get devicesLinkThisDevice;

  /// No description provided for @devicesAlreadyEnrolled.
  ///
  /// In pl, this message translates to:
  /// **'Inna instalacja tego konta już włączyła łączenie. Urządzenia można dodawać tylko z tamtego urządzenia.'**
  String get devicesAlreadyEnrolled;

  /// No description provided for @devicesEnrollFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się włączyć łączenia. Spróbuj ponownie.'**
  String get devicesEnrollFailed;

  /// No description provided for @devicesChainInvalid.
  ///
  /// In pl, this message translates to:
  /// **'Nie można zweryfikować listy urządzeń. Spróbuj ponownie później.'**
  String get devicesChainInvalid;

  /// No description provided for @devicesRevokedBadge.
  ///
  /// In pl, this message translates to:
  /// **'cofnięte'**
  String get devicesRevokedBadge;

  /// No description provided for @devicesPrimaryBadge.
  ///
  /// In pl, this message translates to:
  /// **'główne'**
  String get devicesPrimaryBadge;

  /// No description provided for @devicesThisDeviceKeyless.
  ///
  /// In pl, this message translates to:
  /// **'To urządzenie nie ma jeszcze kluczy. Połącz je ze swoim głównym urządzeniem.'**
  String get devicesThisDeviceKeyless;

  /// No description provided for @linkPrimaryTitle.
  ///
  /// In pl, this message translates to:
  /// **'Połącz urządzenie'**
  String get linkPrimaryTitle;

  /// No description provided for @linkPrimaryExplainer.
  ///
  /// In pl, this message translates to:
  /// **'Na nowym urządzeniu wybierz „Połącz to urządzenie”, a potem wpisz tutaj wyświetlony kod.'**
  String get linkPrimaryExplainer;

  /// No description provided for @linkPrimaryCodeLabel.
  ///
  /// In pl, this message translates to:
  /// **'Kod z nowego urządzenia'**
  String get linkPrimaryCodeLabel;

  /// No description provided for @linkPrimaryContinue.
  ///
  /// In pl, this message translates to:
  /// **'Dalej'**
  String get linkPrimaryContinue;

  /// No description provided for @linkSasHeading.
  ///
  /// In pl, this message translates to:
  /// **'Porównaj kody'**
  String get linkSasHeading;

  /// No description provided for @linkSasExplainer.
  ///
  /// In pl, this message translates to:
  /// **'Oba urządzenia muszą pokazywać ten sam kod. Zatwierdź tylko wtedy, gdy są identyczne.'**
  String get linkSasExplainer;

  /// No description provided for @linkApprove.
  ///
  /// In pl, this message translates to:
  /// **'Zatwierdź'**
  String get linkApprove;

  /// No description provided for @linkCancel.
  ///
  /// In pl, this message translates to:
  /// **'Anuluj'**
  String get linkCancel;

  /// No description provided for @linkWaitingForDevice.
  ///
  /// In pl, this message translates to:
  /// **'Czekam na nowe urządzenie…'**
  String get linkWaitingForDevice;

  /// No description provided for @linkPrimaryDone.
  ///
  /// In pl, this message translates to:
  /// **'Urządzenie zostało połączone.'**
  String get linkPrimaryDone;

  /// No description provided for @linkInvalidCode.
  ///
  /// In pl, this message translates to:
  /// **'Nieprawidłowy kod. Przepisz go dokładnie z nowego urządzenia.'**
  String get linkInvalidCode;

  /// No description provided for @linkNoDak.
  ///
  /// In pl, this message translates to:
  /// **'Brak klucza autoryzacji na tym urządzeniu. Łączyć można tylko z urządzenia, które włączyło łączenie.'**
  String get linkNoDak;

  /// No description provided for @linkFailed.
  ///
  /// In pl, this message translates to:
  /// **'Łączenie nie powiodło się'**
  String get linkFailed;

  /// No description provided for @linkStaleVersionRetry.
  ///
  /// In pl, this message translates to:
  /// **'Lista urządzeń zmieniła się w trakcie — podpisuję ponownie…'**
  String get linkStaleVersionRetry;

  /// No description provided for @linkNewTitle.
  ///
  /// In pl, this message translates to:
  /// **'Połącz to urządzenie'**
  String get linkNewTitle;

  /// No description provided for @linkNewExplainer.
  ///
  /// In pl, this message translates to:
  /// **'Pokaż ten kod na głównym urządzeniu: wybierz tam „Połącz urządzenie” i przepisz kod (albo zeskanuj QR).'**
  String get linkNewExplainer;

  /// No description provided for @linkNewWaitingHello.
  ///
  /// In pl, this message translates to:
  /// **'Czekam na główne urządzenie…'**
  String get linkNewWaitingHello;

  /// No description provided for @linkNewCopy.
  ///
  /// In pl, this message translates to:
  /// **'Skopiuj kod'**
  String get linkNewCopy;

  /// No description provided for @linkNewCopied.
  ///
  /// In pl, this message translates to:
  /// **'Kod skopiowany'**
  String get linkNewCopied;

  /// No description provided for @linkNewCompleting.
  ///
  /// In pl, this message translates to:
  /// **'Łączenie…'**
  String get linkNewCompleting;

  /// No description provided for @linkNewRebinding.
  ///
  /// In pl, this message translates to:
  /// **'Przełączam sesję na nowe urządzenie…'**
  String get linkNewRebinding;

  /// No description provided for @linkNewDone.
  ///
  /// In pl, this message translates to:
  /// **'To urządzenie jest połączone i gotowe.'**
  String get linkNewDone;

  /// No description provided for @linkNewAborted.
  ///
  /// In pl, this message translates to:
  /// **'Łączenie przerwane'**
  String get linkNewAborted;

  /// No description provided for @linkNewRetry.
  ///
  /// In pl, this message translates to:
  /// **'Spróbuj ponownie'**
  String get linkNewRetry;

  /// No description provided for @linkAbortReasonExpired.
  ///
  /// In pl, this message translates to:
  /// **'Kod wygasł.'**
  String get linkAbortReasonExpired;

  /// No description provided for @linkAbortReasonCancelled.
  ///
  /// In pl, this message translates to:
  /// **'Łączenie anulowano na drugim urządzeniu.'**
  String get linkAbortReasonCancelled;

  /// No description provided for @linkAbortReasonBadBlob.
  ///
  /// In pl, this message translates to:
  /// **'Weryfikacja danych nie powiodła się. Klucze zostały usunięte z tego urządzenia.'**
  String get linkAbortReasonBadBlob;

  /// No description provided for @settingsAppVersion.
  ///
  /// In pl, this message translates to:
  /// **'Wersja aplikacji'**
  String get settingsAppVersion;

  /// No description provided for @settingsAboutFireplace.
  ///
  /// In pl, this message translates to:
  /// **'O projekcie'**
  String get settingsAboutFireplace;

  /// No description provided for @settingsSectionPreferences.
  ///
  /// In pl, this message translates to:
  /// **'PREFERENCJE'**
  String get settingsSectionPreferences;

  /// No description provided for @settingsSectionSecurity.
  ///
  /// In pl, this message translates to:
  /// **'BEZPIECZEŃSTWO'**
  String get settingsSectionSecurity;

  /// No description provided for @settingsSectionSession.
  ///
  /// In pl, this message translates to:
  /// **'SESJA'**
  String get settingsSectionSession;

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

  /// No description provided for @deleteAllLocalHistoryTitle.
  ///
  /// In pl, this message translates to:
  /// **'Usuń wszystkie wiadomości z tego urządzenia'**
  String get deleteAllLocalHistoryTitle;

  /// No description provided for @deleteAllLocalHistoryDescription.
  ///
  /// In pl, this message translates to:
  /// **'Trwale usuwa z tego urządzenia wszystkie zapisane wiadomości, w tym pobrane notatki głosowe. Nie usuwa konta, wiadomości z urządzenia drugiej osoby ani kluczy i sesji szyfrowania. Tej operacji nie można cofnąć: serwer przechowywał wyłącznie zaszyfrowane dane, których nie potrafi odczytać, więc nie ma kopii do przywrócenia.'**
  String get deleteAllLocalHistoryDescription;

  /// No description provided for @deleteAllLocalHistoryButton.
  ///
  /// In pl, this message translates to:
  /// **'Usuń trwale wszystkie lokalne wiadomości'**
  String get deleteAllLocalHistoryButton;

  /// No description provided for @deleteAllLocalHistoryDialogTitle.
  ///
  /// In pl, this message translates to:
  /// **'Trwale usunąć wszystkie lokalne wiadomości?'**
  String get deleteAllLocalHistoryDialogTitle;

  /// No description provided for @deleteAllLocalHistoryDialogBody.
  ///
  /// In pl, this message translates to:
  /// **'Ta operacja trwale usuwa z tego urządzenia wszystkie wiadomości i pobrane notatki głosowe. Nie można jej cofnąć — serwer przechowywał wyłącznie zaszyfrowane dane, których nie potrafi odczytać, więc nie ma kopii do przywrócenia. Twoje konto, klucze i sesje szyfrowania pozostaną bez zmian.'**
  String get deleteAllLocalHistoryDialogBody;

  /// No description provided for @deleteAllLocalHistoryConfirm.
  ///
  /// In pl, this message translates to:
  /// **'Usuń trwale'**
  String get deleteAllLocalHistoryConfirm;

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

  /// No description provided for @invitations.
  ///
  /// In pl, this message translates to:
  /// **'Zaproszenia'**
  String get invitations;

  /// No description provided for @invitationsWaitingForYou.
  ///
  /// In pl, this message translates to:
  /// **'Czeka na Ciebie'**
  String get invitationsWaitingForYou;

  /// No description provided for @invitationsSent.
  ///
  /// In pl, this message translates to:
  /// **'Wysłane'**
  String get invitationsSent;

  /// No description provided for @invitationsNothingWaiting.
  ///
  /// In pl, this message translates to:
  /// **'Nic na Ciebie nie czeka'**
  String get invitationsNothingWaiting;

  /// No description provided for @invitationsNoneSent.
  ///
  /// In pl, this message translates to:
  /// **'Brak wysłanych zaproszeń'**
  String get invitationsNoneSent;

  /// No description provided for @inviteByHandleHint.
  ///
  /// In pl, this message translates to:
  /// **'Zaproś kogoś po username#tag. Swój #tag znajdziesz w Ustawieniach przy nicku.'**
  String get inviteByHandleHint;

  /// No description provided for @usernameTagPlaceholder.
  ///
  /// In pl, this message translates to:
  /// **'username#1234'**
  String get usernameTagPlaceholder;

  /// No description provided for @sendInvitation.
  ///
  /// In pl, this message translates to:
  /// **'Wyślij zaproszenie'**
  String get sendInvitation;

  /// No description provided for @invitationFindUser.
  ///
  /// In pl, this message translates to:
  /// **'Znajdź użytkownika'**
  String get invitationFindUser;

  /// No description provided for @userNotFound.
  ///
  /// In pl, this message translates to:
  /// **'Nie znaleziono użytkownika'**
  String get userNotFound;

  /// No description provided for @invitationWantsToConnect.
  ///
  /// In pl, this message translates to:
  /// **'Chce się połączyć'**
  String get invitationWantsToConnect;

  /// No description provided for @invitationWaitingForResponse.
  ///
  /// In pl, this message translates to:
  /// **'Czeka na odpowiedź'**
  String get invitationWaitingForResponse;

  /// No description provided for @invitationAccepted.
  ///
  /// In pl, this message translates to:
  /// **'Zaproszenie zaakceptowane'**
  String get invitationAccepted;

  /// No description provided for @invitationChatReady.
  ///
  /// In pl, this message translates to:
  /// **'Czat gotowy'**
  String get invitationChatReady;

  /// No description provided for @invitationChatNeedsRetry.
  ///
  /// In pl, this message translates to:
  /// **'Czat wymaga ponowienia'**
  String get invitationChatNeedsRetry;

  /// No description provided for @invitationOpenChat.
  ///
  /// In pl, this message translates to:
  /// **'Otwórz czat'**
  String get invitationOpenChat;

  /// No description provided for @invitationCreateChat.
  ///
  /// In pl, this message translates to:
  /// **'Utwórz czat'**
  String get invitationCreateChat;

  /// No description provided for @invitationDone.
  ///
  /// In pl, this message translates to:
  /// **'Gotowe'**
  String get invitationDone;

  /// No description provided for @invitationDecline.
  ///
  /// In pl, this message translates to:
  /// **'Odrzuć'**
  String get invitationDecline;

  /// No description provided for @accept.
  ///
  /// In pl, this message translates to:
  /// **'Zaakceptuj'**
  String get accept;

  /// No description provided for @invitationStatusPending.
  ///
  /// In pl, this message translates to:
  /// **'Oczekuje'**
  String get invitationStatusPending;

  /// No description provided for @invitationSendFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się wysłać zaproszenia'**
  String get invitationSendFailed;

  /// No description provided for @invitationAcceptFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się zaakceptować zaproszenia'**
  String get invitationAcceptFailed;

  /// No description provided for @invitationDeclineFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się odrzucić zaproszenia'**
  String get invitationDeclineFailed;

  /// No description provided for @invitationChatSetupFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się utworzyć czatu'**
  String get invitationChatSetupFailed;

  /// No description provided for @invitationFailedUserNotFound.
  ///
  /// In pl, this message translates to:
  /// **'Ten użytkownik już nie istnieje'**
  String get invitationFailedUserNotFound;

  /// No description provided for @invitationFailedSelf.
  ///
  /// In pl, this message translates to:
  /// **'Nie możesz zaprosić samego siebie'**
  String get invitationFailedSelf;

  /// No description provided for @invitationFailedBlocked.
  ///
  /// In pl, this message translates to:
  /// **'Nie możesz zaprosić tego użytkownika'**
  String get invitationFailedBlocked;

  /// No description provided for @invitationFailedAlreadyFriends.
  ///
  /// In pl, this message translates to:
  /// **'Już jesteście połączeni'**
  String get invitationFailedAlreadyFriends;

  /// No description provided for @invitationFailedDuplicate.
  ///
  /// In pl, this message translates to:
  /// **'Zaproszenie zostało już wysłane'**
  String get invitationFailedDuplicate;

  /// No description provided for @invitationFailedInvalidPayload.
  ///
  /// In pl, this message translates to:
  /// **'Coś było nie tak z tym żądaniem'**
  String get invitationFailedInvalidPayload;

  /// No description provided for @invitationFailedNotFriends.
  ///
  /// In pl, this message translates to:
  /// **'Nie jesteś połączony z tym użytkownikiem'**
  String get invitationFailedNotFriends;

  /// No description provided for @invitationSemanticIncoming.
  ///
  /// In pl, this message translates to:
  /// **'{name}, otrzymane zaproszenie, chce się połączyć'**
  String invitationSemanticIncoming(String name);

  /// No description provided for @invitationSemanticOutgoing.
  ///
  /// In pl, this message translates to:
  /// **'{name}, wysłane zaproszenie, czeka na odpowiedź'**
  String invitationSemanticOutgoing(String name);

  /// No description provided for @invitationSemanticAcceptedReady.
  ///
  /// In pl, this message translates to:
  /// **'{name}, zaproszenie zaakceptowane, czat gotowy'**
  String invitationSemanticAcceptedReady(String name);

  /// No description provided for @invitationSemanticAcceptedNotReady.
  ///
  /// In pl, this message translates to:
  /// **'{name}, zaproszenie zaakceptowane, czat wymaga ponowienia'**
  String invitationSemanticAcceptedNotReady(String name);

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

  /// No description provided for @decryptingMessage.
  ///
  /// In pl, this message translates to:
  /// **'Odszyfrowywanie…'**
  String get decryptingMessage;

  /// No description provided for @messageNoLongerStoredOnThisDevice.
  ///
  /// In pl, this message translates to:
  /// **'Ta wiadomość nie jest już przechowywana na tym urządzeniu.'**
  String get messageNoLongerStoredOnThisDevice;

  /// No description provided for @encryptionNotInitialized.
  ///
  /// In pl, this message translates to:
  /// **'Szyfrowanie niezainicjowane'**
  String get encryptionNotInitialized;

  /// No description provided for @identityDamagedTitle.
  ///
  /// In pl, this message translates to:
  /// **'Brak kluczy szyfrowania na tym urządzeniu'**
  String get identityDamagedTitle;

  /// No description provided for @identityDamagedBody.
  ///
  /// In pl, this message translates to:
  /// **'Logujesz się na nowym urządzeniu lub w nowej przeglądarce? Twoje konto ma już klucze szyfrowania gdzie indziej, a to urządzenie ich nie ma. Jeśli to Twoje dotychczasowe urządzenie, zapisane klucze zostały utracone. Tak czy inaczej nic nie zostało odtworzone automatycznie — zrobienie tego po cichu zniszczyłoby możliwość odczytania historii.'**
  String get identityDamagedBody;

  /// No description provided for @identityDamagedAction.
  ///
  /// In pl, this message translates to:
  /// **'Zacznij od nowa'**
  String get identityDamagedAction;

  /// No description provided for @identityDamagedConfirmTitle.
  ///
  /// In pl, this message translates to:
  /// **'Utworzyć nowe klucze?'**
  String get identityDamagedConfirmTitle;

  /// No description provided for @identityDamagedConfirmBody.
  ///
  /// In pl, this message translates to:
  /// **'Zostanie utworzona nowa tożsamość, a kontakty automatycznie wymienią klucze. Wiadomości już otwarte na tym urządzeniu pozostaną czytelne. Wiadomości, których to urządzenie nigdy nie odszyfrowało, będą nie do odzyskania.'**
  String get identityDamagedConfirmBody;

  /// No description provided for @identityDamagedConfirmAction.
  ///
  /// In pl, this message translates to:
  /// **'Utwórz nowe klucze'**
  String get identityDamagedConfirmAction;

  /// No description provided for @peerIdentityMarkVerifiedAction.
  ///
  /// In pl, this message translates to:
  /// **'Odciski się zgadzają'**
  String get peerIdentityMarkVerifiedAction;

  /// No description provided for @peerIdentityVerifyMenuAction.
  ///
  /// In pl, this message translates to:
  /// **'Zweryfikuj klucze bezpieczeństwa'**
  String get peerIdentityVerifyMenuAction;

  /// No description provided for @peerIdentityFingerprintDialogTitle.
  ///
  /// In pl, this message translates to:
  /// **'Zweryfikuj klucze bezpieczeństwa'**
  String get peerIdentityFingerprintDialogTitle;

  /// No description provided for @peerIdentityFingerprintDialogDescription.
  ///
  /// In pl, this message translates to:
  /// **'Porównaj te odciski z użytkownikiem {name} za pośrednictwem innego kanału. Muszą być identyczne.'**
  String peerIdentityFingerprintDialogDescription(String name);

  /// No description provided for @peerIdentityFingerprintPeerLabel.
  ///
  /// In pl, this message translates to:
  /// **'Odcisk tożsamości użytkownika {name}'**
  String peerIdentityFingerprintPeerLabel(String name);

  /// No description provided for @peerIdentityFingerprintNoStoredKey.
  ///
  /// In pl, this message translates to:
  /// **'Brak zapisanego klucza tożsamości dla tego kontaktu.'**
  String get peerIdentityFingerprintNoStoredKey;

  /// No description provided for @peerIdentityChangedTimelineRow.
  ///
  /// In pl, this message translates to:
  /// **'Klucze bezpieczeństwa {name} uległy zmianie — zwykle to logowanie z nowego urządzenia lub przeglądarki. Dotknij, aby zweryfikować.'**
  String peerIdentityChangedTimelineRow(String name);

  /// No description provided for @ownIdentityReplacedTitle.
  ///
  /// In pl, this message translates to:
  /// **'Nowe klucze szyfrowania na Twoim koncie'**
  String get ownIdentityReplacedTitle;

  /// No description provided for @ownIdentityReplacedBody.
  ///
  /// In pl, this message translates to:
  /// **'Inne logowanie przesłało nowe klucze szyfrowania dla Twojego konta — zwykle to nowe urządzenie, przeglądarka lub ponowna instalacja. Jeśli to nie Ty, natychmiast zmień hasło.'**
  String get ownIdentityReplacedBody;

  /// No description provided for @ownIdentityReplacedDismissAction.
  ///
  /// In pl, this message translates to:
  /// **'Rozumiem'**
  String get ownIdentityReplacedDismissAction;

  /// No description provided for @identityResetPendingTitle.
  ///
  /// In pl, this message translates to:
  /// **'Ktoś poprosił o zresetowanie Twoich kluczy szyfrowania'**
  String get identityResetPendingTitle;

  /// No description provided for @identityResetPendingBody.
  ///
  /// In pl, this message translates to:
  /// **'Jeśli to nie Ty, anuluj teraz — w przeciwnym razie za {remaining} Twoje konto otrzyma nowe klucze szyfrowania, a historia wiadomości stanie się nieczytelna.'**
  String identityResetPendingBody(String remaining);

  /// No description provided for @identityResetCancelAction.
  ///
  /// In pl, this message translates to:
  /// **'Anuluj'**
  String get identityResetCancelAction;

  /// No description provided for @identityResetHoursLeft.
  ///
  /// In pl, this message translates to:
  /// **'{hours, plural, =1{1 godzinę} few{{hours} godziny} other{{hours} godzin}}'**
  String identityResetHoursLeft(int hours);

  /// No description provided for @identityResetMinutesLeft.
  ///
  /// In pl, this message translates to:
  /// **'{minutes, plural, =0{niecałą minutę} =1{1 minutę} few{{minutes} minuty} other{{minutes} minut}}'**
  String identityResetMinutesLeft(int minutes);

  /// No description provided for @identityResetAnyMoment.
  ///
  /// In pl, this message translates to:
  /// **'lada chwila'**
  String get identityResetAnyMoment;

  /// No description provided for @identityUploadLockedTitle.
  ///
  /// In pl, this message translates to:
  /// **'Twoje nowe klucze szyfrowania nie zostały opublikowane'**
  String get identityUploadLockedTitle;

  /// No description provided for @identityUploadLockedBody.
  ///
  /// In pl, this message translates to:
  /// **'To urządzenie utworzyło nowe klucze, ale konto nadal używa poprzednich, więc inne osoby nie mogą się z Tobą bezpiecznie skontaktować. Rozpocznij reset, aby opublikować te klucze — trwa 72 godziny, a wszystkie zalogowane sesje otrzymają powiadomienie.'**
  String get identityUploadLockedBody;

  /// No description provided for @identityResetStartAction.
  ///
  /// In pl, this message translates to:
  /// **'Rozpocznij reset'**
  String get identityResetStartAction;

  /// No description provided for @recoveryKeyTitle.
  ///
  /// In pl, this message translates to:
  /// **'Klucz odzyskiwania'**
  String get recoveryKeyTitle;

  /// No description provided for @recoveryKeySubtitle.
  ///
  /// In pl, this message translates to:
  /// **'Szybszy powrót, jeśli stracisz klucze'**
  String get recoveryKeySubtitle;

  /// No description provided for @recoveryKeyExplainer.
  ///
  /// In pl, this message translates to:
  /// **'Jeśli kiedykolwiek stracisz dostęp do swoich kluczy szyfrowania, uzyskanie nowych trwa 72 godziny — to celowe opóźnienie, dzięki któremu nikt inny nie przejmie po cichu Twojego konta, zanim zdążysz zareagować. Klucz odzyskiwania skraca to oczekiwanie do 1 godziny. Nigdy go nie pomija, a wszystkie zalogowane sesje i tak otrzymają powiadomienie.\n\nSłowa pokazujemy tylko raz i nie zapisujemy ich na tym urządzeniu — przechowywanie ich tutaj oznaczałoby utratę dokładnie wtedy, gdy są potrzebne. Zapisz je w bezpiecznym miejscu, poza urządzeniem.'**
  String get recoveryKeyExplainer;

  /// No description provided for @recoveryKeyGenerateAction.
  ///
  /// In pl, this message translates to:
  /// **'Wygeneruj klucz odzyskiwania'**
  String get recoveryKeyGenerateAction;

  /// No description provided for @recoveryKeyShownOnceWarning.
  ///
  /// In pl, this message translates to:
  /// **'Te słowa pokazujemy tylko raz. Zapisz je, zanim przejdziesz dalej — wygenerowanie nowego klucza zastąpi ten.'**
  String get recoveryKeyShownOnceWarning;

  /// No description provided for @recoveryKeyCopyAction.
  ///
  /// In pl, this message translates to:
  /// **'Kopiuj słowa'**
  String get recoveryKeyCopyAction;

  /// No description provided for @recoveryKeyCopied.
  ///
  /// In pl, this message translates to:
  /// **'Skopiowano klucz odzyskiwania'**
  String get recoveryKeyCopied;

  /// No description provided for @recoveryKeySavedAction.
  ///
  /// In pl, this message translates to:
  /// **'Zapisałem/am'**
  String get recoveryKeySavedAction;

  /// No description provided for @recoveryKeySaved.
  ///
  /// In pl, this message translates to:
  /// **'Zapisano klucz odzyskiwania'**
  String get recoveryKeySaved;

  /// No description provided for @recoveryKeySaveFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się zapisać klucza odzyskiwania — nic nie zostało zapisane, więc te słowa nie zadziałają. Spróbuj ponownie.'**
  String get recoveryKeySaveFailed;

  /// No description provided for @recoveryPhrasePromptTitle.
  ///
  /// In pl, this message translates to:
  /// **'Masz klucz odzyskiwania?'**
  String get recoveryPhrasePromptTitle;

  /// No description provided for @recoveryPhrasePromptBody.
  ///
  /// In pl, this message translates to:
  /// **'Wpisanie 12 słów skraca oczekiwanie z 72 godzin do 1. Tak czy inaczej wszystkie zalogowane sesje otrzymają powiadomienie, a reset nadal można anulować.'**
  String get recoveryPhrasePromptBody;

  /// No description provided for @recoveryPhrasePromptHint.
  ///
  /// In pl, this message translates to:
  /// **'dwanaście słów oddzielonych spacjami'**
  String get recoveryPhrasePromptHint;

  /// No description provided for @recoveryPhraseMalformed.
  ///
  /// In pl, this message translates to:
  /// **'To nie wygląda na kompletny 12-słowny klucz odzyskiwania. Sprawdź literówki.'**
  String get recoveryPhraseMalformed;

  /// No description provided for @recoveryPhraseUseAction.
  ///
  /// In pl, this message translates to:
  /// **'Użyj klucza'**
  String get recoveryPhraseUseAction;

  /// No description provided for @recoveryPhraseNoneAction.
  ///
  /// In pl, this message translates to:
  /// **'Nie mam go'**
  String get recoveryPhraseNoneAction;

  /// No description provided for @identityResetStarted.
  ///
  /// In pl, this message translates to:
  /// **'Reset rozpoczęty. Wszystkie zalogowane sesje zostały powiadomione, a do końca odliczania można go anulować.'**
  String get identityResetStarted;

  /// No description provided for @identityResetAlreadyRunning.
  ///
  /// In pl, this message translates to:
  /// **'Dla tego konta reset już trwa. Odliczanie na górze ekranu pokazuje, ile zostało czasu.'**
  String get identityResetAlreadyRunning;

  /// No description provided for @identityResetCooldown.
  ///
  /// In pl, this message translates to:
  /// **'Reset został niedawno anulowany, więc nowy nie może ruszyć przez maksymalnie 24 godziny. Jeśli ktoś inny wciąż go anuluje, najpierw zmień hasło, aby go wylogować.'**
  String get identityResetCooldown;

  /// No description provided for @identityResetPhraseRejected.
  ///
  /// In pl, this message translates to:
  /// **'Te 12 słów nie pasuje do klucza odzyskiwania zapisanego dla tego konta. Możesz spróbować ponownie albo rozpocząć reset bez klucza i poczekać 72 godziny.'**
  String get identityResetPhraseRejected;

  /// No description provided for @identityResetPhraseLocked.
  ///
  /// In pl, this message translates to:
  /// **'Zbyt wiele prób z kluczem odzyskiwania. Spróbuj ponownie za około godzinę albo rozpocznij reset bez klucza i poczekaj 72 godziny.'**
  String get identityResetPhraseLocked;

  /// No description provided for @identityResetNoAnswer.
  ///
  /// In pl, this message translates to:
  /// **'Brak odpowiedzi serwera, więc nic nie zostało rozpoczęte. Sprawdź połączenie i spróbuj ponownie.'**
  String get identityResetNoAnswer;

  /// No description provided for @identityFingerprintUnavailable.
  ///
  /// In pl, this message translates to:
  /// **'Odcisk tożsamości jest niedostępny.'**
  String get identityFingerprintUnavailable;

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

  /// No description provided for @attachmentOptionDocument.
  ///
  /// In pl, this message translates to:
  /// **'Dokument'**
  String get attachmentOptionDocument;

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

  /// No description provided for @contactNetworkLocalNode.
  ///
  /// In pl, this message translates to:
  /// **'WĘZEŁ LOKALNY'**
  String get contactNetworkLocalNode;

  /// No description provided for @contactNetworkYouLocalNode.
  ///
  /// In pl, this message translates to:
  /// **'Ty, węzeł lokalny'**
  String get contactNetworkYouLocalNode;

  /// No description provided for @contactNetworkSemantic.
  ///
  /// In pl, this message translates to:
  /// **'Sieć kontaktów, {count} kontaktów'**
  String contactNetworkSemantic(num count);

  /// No description provided for @contactNetworkNodes.
  ///
  /// In pl, this message translates to:
  /// **'WĘZŁY {count}'**
  String contactNetworkNodes(String count);

  /// No description provided for @contactNetworkShowList.
  ///
  /// In pl, this message translates to:
  /// **'Widok listy'**
  String get contactNetworkShowList;

  /// No description provided for @contactNetworkShowMap.
  ///
  /// In pl, this message translates to:
  /// **'Widok sieci'**
  String get contactNetworkShowMap;

  /// No description provided for @contactNetworkOpenChatHint.
  ///
  /// In pl, this message translates to:
  /// **'Otwórz czat'**
  String get contactNetworkOpenChatHint;

  /// No description provided for @contactNetworkAddSlot.
  ///
  /// In pl, this message translates to:
  /// **'dodaj'**
  String get contactNetworkAddSlot;

  /// No description provided for @contactNetworkAddSlotSemantic.
  ///
  /// In pl, this message translates to:
  /// **'Dodaj kontakt'**
  String get contactNetworkAddSlotSemantic;

  /// No description provided for @contactNetworkPendingRequests.
  ///
  /// In pl, this message translates to:
  /// **'{count, plural, =1{1 zaproszenie oczekuje} few{{count} zaproszenia oczekują} many{{count} zaproszeń oczekuje} other{{count} zaproszeń oczekuje}}'**
  String contactNetworkPendingRequests(num count);

  /// No description provided for @contactsSearchHint.
  ///
  /// In pl, this message translates to:
  /// **'Szukaj kontaktów'**
  String get contactsSearchHint;

  /// No description provided for @contactsSearchNoResults.
  ///
  /// In pl, this message translates to:
  /// **'Brak pasujących kontaktów'**
  String get contactsSearchNoResults;

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

  /// No description provided for @sessionEndedReason.
  ///
  /// In pl, this message translates to:
  /// **'wylogowano: {reason}'**
  String sessionEndedReason(String reason);

  /// No description provided for @authTagline.
  ///
  /// In pl, this message translates to:
  /// **'Wiadomości, które przeczytają tylko dwie osoby'**
  String get authTagline;

  /// No description provided for @authLoginTab.
  ///
  /// In pl, this message translates to:
  /// **'LOGOWANIE'**
  String get authLoginTab;

  /// No description provided for @authRegisterTab.
  ///
  /// In pl, this message translates to:
  /// **'REJESTRACJA'**
  String get authRegisterTab;

  /// No description provided for @authUsernameHint.
  ///
  /// In pl, this message translates to:
  /// **'Nazwa użytkownika'**
  String get authUsernameHint;

  /// No description provided for @authUsernameRequired.
  ///
  /// In pl, this message translates to:
  /// **'Nazwa użytkownika jest wymagana'**
  String get authUsernameRequired;

  /// No description provided for @authPasswordHint.
  ///
  /// In pl, this message translates to:
  /// **'Hasło'**
  String get authPasswordHint;

  /// No description provided for @authPasswordHintRegister.
  ///
  /// In pl, this message translates to:
  /// **'Hasło (min. 8 znaków)'**
  String get authPasswordHintRegister;

  /// No description provided for @authLoginButton.
  ///
  /// In pl, this message translates to:
  /// **'Zaloguj się'**
  String get authLoginButton;

  /// No description provided for @authCreateAccountButton.
  ///
  /// In pl, this message translates to:
  /// **'Utwórz konto'**
  String get authCreateAccountButton;

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

  /// No description provided for @antiQuantumNoteBurnedTitle.
  ///
  /// In pl, this message translates to:
  /// **'Notatka zniszczona'**
  String get antiQuantumNoteBurnedTitle;

  /// No description provided for @antiQuantumNoteBurnedSubtitle.
  ///
  /// In pl, this message translates to:
  /// **'została odczytana'**
  String get antiQuantumNoteBurnedSubtitle;

  /// No description provided for @antiQuantumNoteRevealWarning.
  ///
  /// In pl, this message translates to:
  /// **'Tę notatkę można odczytać tylko raz. Odsłonięcie zniszczy ją trwale — dla wszystkich, na zawsze.'**
  String get antiQuantumNoteRevealWarning;

  /// No description provided for @antiQuantumNoteRevealConfirm.
  ///
  /// In pl, this message translates to:
  /// **'Odsłoń i zniszcz'**
  String get antiQuantumNoteRevealConfirm;

  /// No description provided for @antiQuantumNoteRevealLoading.
  ///
  /// In pl, this message translates to:
  /// **'Odszyfrowywanie…'**
  String get antiQuantumNoteRevealLoading;

  /// No description provided for @antiQuantumNoteRevealedHeader.
  ///
  /// In pl, this message translates to:
  /// **'Wiadomość odsłonięta · trwale zniszczona'**
  String get antiQuantumNoteRevealedHeader;

  /// No description provided for @antiQuantumNoteRevealedFooter.
  ///
  /// In pl, this message translates to:
  /// **'Notatka została usunięta z serwera. Widać ją już tylko na tym ekranie.'**
  String get antiQuantumNoteRevealedFooter;

  /// No description provided for @antiQuantumNoteRevealClose.
  ///
  /// In pl, this message translates to:
  /// **'Zamknij'**
  String get antiQuantumNoteRevealClose;

  /// No description provided for @antiQuantumNoteRevealRetry.
  ///
  /// In pl, this message translates to:
  /// **'Spróbuj ponownie'**
  String get antiQuantumNoteRevealRetry;

  /// No description provided for @antiQuantumNoteRevealDestroyedBody.
  ///
  /// In pl, this message translates to:
  /// **'Ta notatka została już odczytana i zniszczona. Nie da się jej przywrócić.'**
  String get antiQuantumNoteRevealDestroyedBody;

  /// No description provided for @antiQuantumNoteRevealExpiredTitle.
  ///
  /// In pl, this message translates to:
  /// **'Notatka wygasła'**
  String get antiQuantumNoteRevealExpiredTitle;

  /// No description provided for @antiQuantumNoteRevealExpiredBody.
  ///
  /// In pl, this message translates to:
  /// **'Ta notatka wygasła i zniszczyła się, zanim została odczytana.'**
  String get antiQuantumNoteRevealExpiredBody;

  /// No description provided for @antiQuantumNoteRevealCorruptBody.
  ///
  /// In pl, this message translates to:
  /// **'Notatka została zniszczona, ale nie udało się jej odszyfrować. Link może być uszkodzony.'**
  String get antiQuantumNoteRevealCorruptBody;

  /// No description provided for @antiQuantumNoteRevealInvalidLinkTitle.
  ///
  /// In pl, this message translates to:
  /// **'Uszkodzony link'**
  String get antiQuantumNoteRevealInvalidLinkTitle;

  /// No description provided for @antiQuantumNoteRevealInvalidLinkBody.
  ///
  /// In pl, this message translates to:
  /// **'W tym linku brakuje prawidłowego klucza deszyfrującego. Notatka nie została zniszczona.'**
  String get antiQuantumNoteRevealInvalidLinkBody;

  /// No description provided for @antiQuantumNoteRevealNetworkErrorTitle.
  ///
  /// In pl, this message translates to:
  /// **'Brak połączenia'**
  String get antiQuantumNoteRevealNetworkErrorTitle;

  /// No description provided for @antiQuantumNoteRevealNetworkErrorBody.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się połączyć z serwerem. Sprawdź połączenie i spróbuj ponownie.'**
  String get antiQuantumNoteRevealNetworkErrorBody;

  /// No description provided for @privacyAntiQuantumNoteTitle.
  ///
  /// In pl, this message translates to:
  /// **'Notatki antykwantowe'**
  String get privacyAntiQuantumNoteTitle;

  /// No description provided for @privacyAntiQuantumNoteLead.
  ///
  /// In pl, this message translates to:
  /// **'Samoniszczące wiadomości z własną, drugą warstwą szyfrowania — nawet link nie zdradza sekretu.'**
  String get privacyAntiQuantumNoteLead;

  /// No description provided for @privacyAntiQuantumNotePointDevice.
  ///
  /// In pl, this message translates to:
  /// **'Szyfrowane na Twoim urządzeniu przed wysłaniem — serwer przechowuje wyłącznie nieczytelny szyfrogram.'**
  String get privacyAntiQuantumNotePointDevice;

  /// No description provided for @privacyAntiQuantumNotePointKey.
  ///
  /// In pl, this message translates to:
  /// **'Klucz deszyfrujący podróżuje jedynie we fragmencie linku (#), którego przeglądarki nigdy nie wysyłają do żadnego serwera.'**
  String get privacyAntiQuantumNotePointKey;

  /// No description provided for @privacyAntiQuantumNotePointOnce.
  ///
  /// In pl, this message translates to:
  /// **'Notatkę można odczytać dokładnie raz — po czym jest trwale usuwana.'**
  String get privacyAntiQuantumNotePointOnce;

  /// No description provided for @privacyAntiQuantumNotePointTimer.
  ///
  /// In pl, this message translates to:
  /// **'Nieotwarte notatki niszczą się same po upływie timera (1h–24h), a wiadomość w czacie znika razem z nimi.'**
  String get privacyAntiQuantumNotePointTimer;

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

  /// No description provided for @saveImage.
  ///
  /// In pl, this message translates to:
  /// **'Zapisz obraz'**
  String get saveImage;

  /// No description provided for @copyImage.
  ///
  /// In pl, this message translates to:
  /// **'Kopiuj obraz'**
  String get copyImage;

  /// No description provided for @imageSaved.
  ///
  /// In pl, this message translates to:
  /// **'Zapisano obraz'**
  String get imageSaved;

  /// No description provided for @imageSaveFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się zapisać obrazu'**
  String get imageSaveFailed;

  /// No description provided for @imageCopied.
  ///
  /// In pl, this message translates to:
  /// **'Skopiowano obraz'**
  String get imageCopied;

  /// No description provided for @imageCopyFailed.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się skopiować obrazu'**
  String get imageCopyFailed;

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

  /// No description provided for @messageTooLong.
  ///
  /// In pl, this message translates to:
  /// **'Wiadomość jest za długa, aby ją wysłać'**
  String get messageTooLong;

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

  /// No description provided for @snackbarAllLocalHistoryDeleted.
  ///
  /// In pl, this message translates to:
  /// **'Wszystkie wiadomości zapisane na tym urządzeniu zostały trwale usunięte'**
  String get snackbarAllLocalHistoryDeleted;

  /// No description provided for @snackbarFailedToDeleteAllLocalHistory.
  ///
  /// In pl, this message translates to:
  /// **'Nie udało się usunąć części wiadomości z tego urządzenia. Spróbuj ponownie.'**
  String get snackbarFailedToDeleteAllLocalHistory;

  /// No description provided for @friendAcceptedYourRequest.
  ///
  /// In pl, this message translates to:
  /// **'{name} zaakceptował(a) zaproszenie do znajomych'**
  String friendAcceptedYourRequest(String name);

  /// No description provided for @appearance.
  ///
  /// In pl, this message translates to:
  /// **'Wygląd'**
  String get appearance;

  /// No description provided for @appearanceSummary.
  ///
  /// In pl, this message translates to:
  /// **'{theme} · {background}'**
  String appearanceSummary(String theme, String background);

  /// No description provided for @appearanceColorTheme.
  ///
  /// In pl, this message translates to:
  /// **'MOTYW KOLORYSTYCZNY'**
  String get appearanceColorTheme;

  /// No description provided for @appearanceThemeLight.
  ///
  /// In pl, this message translates to:
  /// **'Alabaster'**
  String get appearanceThemeLight;

  /// No description provided for @appearanceThemeTeal.
  ///
  /// In pl, this message translates to:
  /// **'Turkus'**
  String get appearanceThemeTeal;

  /// No description provided for @appearanceThemeDark.
  ///
  /// In pl, this message translates to:
  /// **'Grafit'**
  String get appearanceThemeDark;

  /// No description provided for @appearanceThemeBlue.
  ///
  /// In pl, this message translates to:
  /// **'Błękit'**
  String get appearanceThemeBlue;

  /// No description provided for @appearanceThemeCosmic.
  ///
  /// In pl, this message translates to:
  /// **'Kosmos'**
  String get appearanceThemeCosmic;

  /// No description provided for @themeOptionLight.
  ///
  /// In pl, this message translates to:
  /// **'Jasny ciepły papier z żarowymi akcentami'**
  String get themeOptionLight;

  /// No description provided for @themeOptionDark.
  ///
  /// In pl, this message translates to:
  /// **'Ciemny neutralny grafit z turkusowymi akcentami'**
  String get themeOptionDark;

  /// No description provided for @themeOptionBlue.
  ///
  /// In pl, this message translates to:
  /// **'Głęboki granat z błękitnymi akcentami'**
  String get themeOptionBlue;

  /// No description provided for @themeOptionTealStone.
  ///
  /// In pl, this message translates to:
  /// **'Jasny chłodny kamień z turkusowymi akcentami'**
  String get themeOptionTealStone;

  /// No description provided for @themeOptionCosmic.
  ///
  /// In pl, this message translates to:
  /// **'Ciemny kosmos z lodowoniebieskim światłem'**
  String get themeOptionCosmic;

  /// No description provided for @appearanceChatBackground.
  ///
  /// In pl, this message translates to:
  /// **'TŁO CZATU'**
  String get appearanceChatBackground;

  /// No description provided for @appearanceBackgroundThemeDefault.
  ///
  /// In pl, this message translates to:
  /// **'Domyślne motywu'**
  String get appearanceBackgroundThemeDefault;

  /// No description provided for @appearanceBackgroundThemeDefaultSubtitle.
  ///
  /// In pl, this message translates to:
  /// **'Dopasowuje się do wybranego motywu'**
  String get appearanceBackgroundThemeDefaultSubtitle;

  /// No description provided for @appearanceBackgroundThemeDefaultCosmicSubtitle.
  ///
  /// In pl, this message translates to:
  /// **'Animowane gwiazdy dla motywu Kosmos'**
  String get appearanceBackgroundThemeDefaultCosmicSubtitle;

  /// No description provided for @appearanceBackgroundPlain.
  ///
  /// In pl, this message translates to:
  /// **'Gładkie'**
  String get appearanceBackgroundPlain;

  /// No description provided for @appearanceBackgroundPlainSubtitle.
  ///
  /// In pl, this message translates to:
  /// **'Jednolite tło w kolorach motywu'**
  String get appearanceBackgroundPlainSubtitle;

  /// No description provided for @appearanceBackgroundGlyphs.
  ///
  /// In pl, this message translates to:
  /// **'Hieroglify'**
  String get appearanceBackgroundGlyphs;

  /// No description provided for @appearanceBackgroundGlyphsSubtitle.
  ///
  /// In pl, this message translates to:
  /// **'Wzór świątynnych kolumn'**
  String get appearanceBackgroundGlyphsSubtitle;

  /// No description provided for @appearanceBackgroundStarfield.
  ///
  /// In pl, this message translates to:
  /// **'Gwiazdy'**
  String get appearanceBackgroundStarfield;

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

  /// No description provided for @userCardAbout.
  ///
  /// In pl, this message translates to:
  /// **'O mnie'**
  String get userCardAbout;

  /// No description provided for @userCardMyProfile.
  ///
  /// In pl, this message translates to:
  /// **'Mój profil'**
  String get userCardMyProfile;

  /// No description provided for @userCardEditAbout.
  ///
  /// In pl, this message translates to:
  /// **'Edytuj opis'**
  String get userCardEditAbout;

  /// No description provided for @userCardAddPhoto.
  ///
  /// In pl, this message translates to:
  /// **'Dodaj zdjęcie'**
  String get userCardAddPhoto;

  /// No description provided for @userCardPhotoLimitReached.
  ///
  /// In pl, this message translates to:
  /// **'Osiągnięto limit zdjęć'**
  String get userCardPhotoLimitReached;

  /// No description provided for @userCardSetMainPhoto.
  ///
  /// In pl, this message translates to:
  /// **'Ustaw jako główne zdjęcie'**
  String get userCardSetMainPhoto;

  /// No description provided for @userCardDeletePhoto.
  ///
  /// In pl, this message translates to:
  /// **'Usuń to zdjęcie'**
  String get userCardDeletePhoto;

  /// No description provided for @userCardSave.
  ///
  /// In pl, this message translates to:
  /// **'Zapisz'**
  String get userCardSave;

  /// No description provided for @userCardCancel.
  ///
  /// In pl, this message translates to:
  /// **'Anuluj'**
  String get userCardCancel;

  /// No description provided for @userCardBack.
  ///
  /// In pl, this message translates to:
  /// **'Wstecz'**
  String get userCardBack;

  /// No description provided for @userCardNotificationsOn.
  ///
  /// In pl, this message translates to:
  /// **'Powiadomienia włączone'**
  String get userCardNotificationsOn;

  /// No description provided for @userCardMuteOneHour.
  ///
  /// In pl, this message translates to:
  /// **'Wycisz na 1 godzinę'**
  String get userCardMuteOneHour;

  /// No description provided for @userCardMuteEightHours.
  ///
  /// In pl, this message translates to:
  /// **'Wycisz na 8 godzin'**
  String get userCardMuteEightHours;

  /// No description provided for @userCardMuteOneWeek.
  ///
  /// In pl, this message translates to:
  /// **'Wycisz na tydzień'**
  String get userCardMuteOneWeek;

  /// No description provided for @userCardMuteForever.
  ///
  /// In pl, this message translates to:
  /// **'Wycisz na zawsze'**
  String get userCardMuteForever;

  /// No description provided for @userCardMessage.
  ///
  /// In pl, this message translates to:
  /// **'Wiadomość'**
  String get userCardMessage;

  /// No description provided for @userCardMute.
  ///
  /// In pl, this message translates to:
  /// **'Wycisz'**
  String get userCardMute;

  /// No description provided for @userCardMuted.
  ///
  /// In pl, this message translates to:
  /// **'Wyciszono'**
  String get userCardMuted;

  /// No description provided for @userCardCopyTag.
  ///
  /// In pl, this message translates to:
  /// **'Kopiuj tag'**
  String get userCardCopyTag;

  /// No description provided for @userCardManagePhotos.
  ///
  /// In pl, this message translates to:
  /// **'Zarządzaj zdjęciami'**
  String get userCardManagePhotos;

  /// No description provided for @userCardPhotoOfCount.
  ///
  /// In pl, this message translates to:
  /// **'Zdjęcie {index} z {count}'**
  String userCardPhotoOfCount(Object index, Object count);

  /// No description provided for @userCardMainPhotoHint.
  ///
  /// In pl, this message translates to:
  /// **'To jest Twoje główne zdjęcie — kontakty widzą je na czatach.'**
  String get userCardMainPhotoHint;

  /// No description provided for @userCardAboutHint.
  ///
  /// In pl, this message translates to:
  /// **'Kilka słów o Tobie'**
  String get userCardAboutHint;

  /// No description provided for @userCardSharedMedia.
  ///
  /// In pl, this message translates to:
  /// **'Udostępnione multimedia'**
  String get userCardSharedMedia;

  /// No description provided for @userCardDragReorderHint.
  ///
  /// In pl, this message translates to:
  /// **'Przytrzymaj i przeciągnij, aby zmienić kolejność — pierwsze zdjęcie jest Twoim głównym.'**
  String get userCardDragReorderHint;

  /// No description provided for @settingsChatBackground.
  ///
  /// In pl, this message translates to:
  /// **'Tło czatu'**
  String get settingsChatBackground;

  /// No description provided for @userCardCopyHandle.
  ///
  /// In pl, this message translates to:
  /// **'Kopiuj nazwę użytkownika i tag'**
  String get userCardCopyHandle;

  /// No description provided for @userCardCopiedHandle.
  ///
  /// In pl, this message translates to:
  /// **'Skopiowano {handle}'**
  String userCardCopiedHandle(Object handle);

  /// No description provided for @userCardNotificationsMuted.
  ///
  /// In pl, this message translates to:
  /// **'Powiadomienia wyciszone'**
  String get userCardNotificationsMuted;

  /// No description provided for @userCardBlockTitle.
  ///
  /// In pl, this message translates to:
  /// **'Zablokować {handle}?'**
  String userCardBlockTitle(Object handle);

  /// No description provided for @userCardBlockConfirm.
  ///
  /// In pl, this message translates to:
  /// **'Nie będzie można wysyłać wiadomości do tego kontaktu.'**
  String get userCardBlockConfirm;

  /// No description provided for @userCardDeletePhotoTitle.
  ///
  /// In pl, this message translates to:
  /// **'Usunąć zdjęcie?'**
  String get userCardDeletePhotoTitle;

  /// No description provided for @userCardDeletePhotoConfirm.
  ///
  /// In pl, this message translates to:
  /// **'To trwale usuwa to zdjęcie profilowe.'**
  String get userCardDeletePhotoConfirm;

  /// No description provided for @userCardSafety.
  ///
  /// In pl, this message translates to:
  /// **'Bezpieczeństwo'**
  String get userCardSafety;

  /// No description provided for @userCardRemoveContact.
  ///
  /// In pl, this message translates to:
  /// **'Usuń kontakt'**
  String get userCardRemoveContact;

  /// No description provided for @messageReadMore.
  ///
  /// In pl, this message translates to:
  /// **'Czytaj więcej'**
  String get messageReadMore;

  /// No description provided for @messageShowLess.
  ///
  /// In pl, this message translates to:
  /// **'Zwiń'**
  String get messageShowLess;

  /// No description provided for @chatPickerTitle.
  ///
  /// In pl, this message translates to:
  /// **'Wybierz znajomego'**
  String get chatPickerTitle;

  /// No description provided for @chatPickerSubtitle.
  ///
  /// In pl, this message translates to:
  /// **'Wybierz węzeł, aby rozpocząć czat'**
  String get chatPickerSubtitle;

  /// No description provided for @chatPickerEmptyTitle.
  ///
  /// In pl, this message translates to:
  /// **'Nie masz jeszcze znajomych'**
  String get chatPickerEmptyTitle;

  /// No description provided for @chatPickerEmptyDescription.
  ///
  /// In pl, this message translates to:
  /// **'Dodaj znajomego, aby rozpocząć czat.'**
  String get chatPickerEmptyDescription;

  /// No description provided for @chatPickerOpenTooltip.
  ///
  /// In pl, this message translates to:
  /// **'Nowy czat'**
  String get chatPickerOpenTooltip;

  /// No description provided for @chatPickerInviteButton.
  ///
  /// In pl, this message translates to:
  /// **'Zaproś kogoś'**
  String get chatPickerInviteButton;

  /// No description provided for @videoMessage.
  ///
  /// In pl, this message translates to:
  /// **'Wideo'**
  String get videoMessage;

  /// No description provided for @videoTooLarge.
  ///
  /// In pl, this message translates to:
  /// **'Wideo jest za duże (maks. 20 MB)'**
  String get videoTooLarge;

  /// No description provided for @videoTooLong.
  ///
  /// In pl, this message translates to:
  /// **'Wideo jest za długie (maks. 60 sekund)'**
  String get videoTooLong;

  /// No description provided for @videoUnsupportedFormat.
  ///
  /// In pl, this message translates to:
  /// **'Nieobsługiwany format wideo (tylko MP4)'**
  String get videoUnsupportedFormat;

  /// No description provided for @attachmentUnsupportedFileType.
  ///
  /// In pl, this message translates to:
  /// **'Nieobsługiwany typ pliku'**
  String get attachmentUnsupportedFileType;
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
