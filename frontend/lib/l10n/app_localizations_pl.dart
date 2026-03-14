// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get appTitle => 'Fireplace';

  @override
  String get settings => 'Ustawienia';

  @override
  String get theme => 'Motyw';

  @override
  String get language => 'Język';

  @override
  String get languagePolish => 'Polski';

  @override
  String get languageEnglish => 'Angielski';

  @override
  String get privacyAndSafety => 'Prywatność i bezpieczeństwo';

  @override
  String get blocked => 'Zablokowani';

  @override
  String get devices => 'Urządzenia';

  @override
  String get resetPassword => 'Zmień hasło';

  @override
  String get deleteAccount => 'Usuń konto';

  @override
  String get logout => 'Wyloguj';

  @override
  String get chat => 'Czat';

  @override
  String get contacts => 'Kontakty';

  @override
  String get profilePictureUpdated => 'Zdjęcie profilowe zaktualizowane';

  @override
  String get uploadFailed => 'Nie udało się przesłać';

  @override
  String get passwordUpdatedSuccessfully => 'Hasło zostało zmienione';

  @override
  String get passwordResetFailed => 'Nie udało się zmienić hasła';

  @override
  String get accountDeletionFailed => 'Nie udało się usunąć konta';

  @override
  String get loading => 'Ładowanie…';

  @override
  String get devicesLoading => 'Ładowanie…';

  @override
  String get privacySafetyTitle => 'Prywatność i bezpieczeństwo';

  @override
  String get e2eEncryptionEnabled => 'Szyfrowanie end-to-end jest włączone';

  @override
  String get e2eEncryptionDescription =>
      'Twoje wiadomości są szyfrowane protokołem Signal. Tylko Ty i odbiorca możecie je odczytać. Serwery Fireplace nie mają dostępu do treści wiadomości.';

  @override
  String get yourEncryptionKeys => 'Twoje klucze szyfrowania';

  @override
  String get yourEncryptionKeysDescription =>
      'Klucze są bezpiecznie przechowywane na tym urządzeniu. Po zmianie urządzenia lub reinstalacji aplikacji zostaną wygenerowane nowe klucze, a poprzedniej historii nie da się odzyskać.';

  @override
  String get singleDeviceEncryption => 'Szyfrowanie na jednym urządzeniu';

  @override
  String get singleDeviceEncryptionDescription =>
      'Każde urządzenie ma własne klucze. Wiadomości są powiązane z urządzeniem, które je wysłało lub odebrało.';

  @override
  String get webKeyStorage => 'Przeglądarka: przechowywanie kluczy';

  @override
  String get webKeyStorageDescription =>
      'W wersji web klucze są przechowywane w przeglądarce (szyfrowane WebCrypto). Osoba z dostępem do tego urządzenia mogłaby je odczytać. Dla maksymalnego bezpieczeństwa używaj aplikacji mobilnej.';

  @override
  String get whatIsEncrypted => 'Co jest szyfrowane';

  @override
  String get whatIsEncryptedDescription =>
      'Wiadomości tekstowe i podglądy linków są szyfrowane end-to-end. Pliki multimedialne (zdjęcia, wiadomości głosowe, rysunki) nie są jeszcze szyfrowane end-to-end.';

  @override
  String get serverStoresMetadata => 'Co przechowuje serwer (metadane)';

  @override
  String get serverStoresMetadataDescription =>
      'Aby dostarczać wiadomości, serwer przechowuje: kto jest w danej rozmowie, kiedy wiadomości zostały wysłane oraz status dostarczenia. Treść wiadomości nigdy nie jest widoczna dla serwera.';

  @override
  String get yourIdentityFingerprint => 'Twój odcisk tożsamości';

  @override
  String get shareFingerprintHint =>
      'Udostępnij go kontaktom, aby zweryfikować tożsamość.';

  @override
  String get addInvitations => 'Dodaj / Zaproszenia';

  @override
  String get addUser => 'Dodaj użytkownika';

  @override
  String get friendRequests => 'Zaproszenia';

  @override
  String friendRequestSentTo(String handle) {
    return 'Zaproszenie wysłane do $handle';
  }

  @override
  String get addNewUserHint =>
      'Dodaj użytkownika po username#tag (np. username#1234). Swój #tag znajdziesz w Ustawieniach przy nicku. Każdy #tag jest unikalny.';

  @override
  String get usernameTagPlaceholder => 'username#1234';

  @override
  String get addNewUser => 'Dodaj użytkownika';

  @override
  String get userNotFound => 'Nie znaleziono użytkownika';

  @override
  String get noPendingRequests => 'Brak oczekujących zaproszeń';

  @override
  String get wantsToAddYouAsFriend => 'chce dodać Cię do znajomych';

  @override
  String get accept => 'Zaakceptuj';

  @override
  String get reject => 'Odrzuć';

  @override
  String friendAdded(String name) {
    return 'Dodano do znajomych: $name';
  }

  @override
  String get requestRejected => 'Zaproszenie odrzucone';

  @override
  String get encryptedMessage => 'Wiadomość zaszyfrowana';

  @override
  String get decryptionFailed => 'Odszyfrowanie nie powiodło się';

  @override
  String get encryptionNotInitialized => 'Szyfrowanie niezainicjowane';

  @override
  String get blockUser => 'Zablokuj użytkownika';

  @override
  String get conversationDeletedByOther => 'Rozmowa usunięta przez drugą osobę';

  @override
  String get noMessagesYet => 'Brak wiadomości';

  @override
  String get cantMessageThisUser => 'Nie możesz pisać do tego użytkownika';

  @override
  String get cantTypeToThisUser => 'Nie możesz pisać do tego użytkownika';

  @override
  String get recordingVoice => 'Nagrywanie głosu…';

  @override
  String get typing => 'pisze…';

  @override
  String get selectAConversation => 'Wybierz rozmowę';

  @override
  String get noConversationsYet => 'Brak czatów';

  @override
  String get startNewChatToBegin => 'Rozpocznij czat, aby zacząć';

  @override
  String get deleteConversationTitle => 'Usuń rozmowę?';

  @override
  String get deleteConversationConfirm =>
      'Wszystkie wiadomości z tej rozmowy zostaną usunięte. Później możesz otworzyć czat z Kontaktów.';

  @override
  String get cancel => 'Anuluj';

  @override
  String get delete => 'Usuń';

  @override
  String get voiceMessage => 'Wiadomość głosowa';

  @override
  String get image => 'Obraz';

  @override
  String get ping => 'Ping';

  @override
  String get unknown => 'Nieznany';

  @override
  String get noBlockedUsers => 'Brak zablokowanych użytkowników';

  @override
  String get unblock => 'Odblokuj';

  @override
  String get removeFriendTitle => 'Usuń z kontaktów?';

  @override
  String removeFriendConfirm(String name) {
    return 'Usunąć $name z kontaktów? Zostanie usunięta cała historia rozmowy.';
  }

  @override
  String get remove => 'Usuń';

  @override
  String get noContactsYet => 'Brak kontaktów';

  @override
  String get addFriendsToStart => 'Dodaj znajomych, aby zacząć pisać';

  @override
  String get block => 'Zablokuj';

  @override
  String get imageFailedToLoad => 'Nie udało się załadować obrazu';

  @override
  String get unsupportedMessageType => 'Nieobsługiwany typ wiadomości';

  @override
  String get resetPasswordDialogTitle => 'Zmień hasło';

  @override
  String get oldPassword => 'Obecne hasło';

  @override
  String get newPassword => 'Nowe hasło';

  @override
  String get passwordRequired => 'Hasło jest wymagane';

  @override
  String get passwordMinLength => 'Hasło musi mieć co najmniej 8 znaków';

  @override
  String get passwordMustContain =>
      'Hasło musi zawierać wielką literę, małą literę i cyfrę';

  @override
  String get oldPasswordRequired => 'Obecne hasło jest wymagane';

  @override
  String get resetButton => 'Zmień';

  @override
  String get deleteAccountDialogTitle => 'Usuń konto';

  @override
  String get deleteAccountWarning =>
      'Ta operacja jest nieodwracalna. Wszystkie Twoje wiadomości i rozmowy zostaną usunięte.';

  @override
  String get enterPasswordToConfirm => 'Wpisz hasło, aby potwierdzić';

  @override
  String get clearingChat => 'Czyszczenie…';
}
