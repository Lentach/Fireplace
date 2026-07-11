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
  String get webPushEnableTitle => 'Włącz powiadomienia push';

  @override
  String get webPushEnableSubtitle =>
      'Na iOS wymagane po dodaniu aplikacji do ekranu głównego';

  @override
  String get webPushEnabled => 'Powiadomienia push włączone';

  @override
  String get webPushPermissionDenied => 'Odrzucono uprawnienie do powiadomień';

  @override
  String get webPushInstallRequired =>
      'Najpierw dodaj Fireplace do ekranu głównego (Safari -> Udostępnij -> Do ekranu początkowego)';

  @override
  String get webPushNotSupported =>
      'Powiadomienia push nie są obsługiwane w tej przeglądarce/sesji';

  @override
  String get webPushNoChanges => 'Powiadomienia push są już włączone';

  @override
  String get webPushEnableFailed => 'Nie udało się włączyć powiadomień push';

  @override
  String get resetPassword => 'Zmień hasło';

  @override
  String get deleteAccount => 'Usuń konto';

  @override
  String get logout => 'Wyloguj';

  @override
  String get uninstallWarning =>
      'Odinstalowanie aplikacji lub wyczyszczenie danych witryny trwale usuwa historię wiadomości — aby odświeżyć, po prostu całkowicie zamknij i otwórz aplikację ponownie.';

  @override
  String get chat => 'Czaty';

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
  String get settingsAppVersion => 'Wersja aplikacji';

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
      'Wszystkie wiadomości są szyfrowane end-to-end (tekst, zdjęcia, głos, linki). Tylko Ty i odbiorca możecie je odczytać.';

  @override
  String get serverStoresMetadata => 'Co przechowuje serwer (metadane)';

  @override
  String get serverStoresMetadataDescription =>
      'Aby dostarczać wiadomości, serwer przechowuje: kto jest w danej rozmowie, kiedy wiadomości zostały wysłane oraz status dostarczenia. Treść wiadomości nigdy nie jest widoczna dla serwera.';

  @override
  String get localMessageCache => 'Lokalna pamięć wiadomości';

  @override
  String get localMessageCacheDescription =>
      'Dla niezawodności to urządzenie może lokalnie przechowywać odszyfrowane podglądy wiadomości i pobrane wiadomości głosowe. Wyczyszczenie tej pamięci nie usuwa kluczy szyfrowania ani historii z serwera.';

  @override
  String get clearLocalMessageCache => 'Wyczyść lokalną pamięć wiadomości';

  @override
  String get yourIdentityFingerprint => 'Twój odcisk tożsamości';

  @override
  String get shareFingerprintHint =>
      'To unikalna reprezentacja Twojego klucza szyfrowania.';

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
  String get chatMessageHint => 'Napisz wiadomość…';

  @override
  String get chatComposerSendTooltip => 'Wyślij';

  @override
  String get chatComposerSendSemantics => 'Wyślij wiadomość';

  @override
  String get chatComposerEmojiTooltip => 'Emoji';

  @override
  String get chatComposerEmojiSemantics => 'Otwórz panel emoji';

  @override
  String get emojiPickerSemantics => 'Panel emoji';

  @override
  String get emojiPickerSearchHint => 'Szukaj emoji';

  @override
  String get emojiPickerNoRecents => 'Brak ostatnich emoji';

  @override
  String emojiPickerEmojiOptionSemantics(String emoji) {
    return 'Emoji $emoji';
  }

  @override
  String get chatDateToday => 'Dziś';

  @override
  String get chatDateYesterday => 'Wczoraj';

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
  String get attachment => 'Załącznik';

  @override
  String get attachmentOptionPhoto => 'Zdjęcie';

  @override
  String get attachmentOptionDocument => 'Dokument';

  @override
  String get actionTileTimer => 'Timer';

  @override
  String get actionTileDisappearingMessages => 'Znikające wiadomości';

  @override
  String get disappearingTimerTitle => 'Znikające wiadomości';

  @override
  String get disappearingTimerExplainerLine1 =>
      'Wiadomości znikają po odczytaniu.';

  @override
  String get disappearingTimerExplainerLine2 =>
      'Odliczanie startuje, gdy ktoś otworzy czat.';

  @override
  String get disappearingTimerExplainerLine3 =>
      'Tylko nowe wiadomości używają ustawionego tu czasu.';

  @override
  String get disappearingTimerRangeHint =>
      'Od 5 sekund do 30 dni; same zera = wyłączone';

  @override
  String get disappearingTimerSetTimer => 'Ustaw timer';

  @override
  String get disappearingTimerTurnOff => 'Wyłącz';

  @override
  String disappearingTimerSummarySemantics(String summary) {
    return 'Wybrany czas: $summary';
  }

  @override
  String disappearingComposerBanner(String duration) {
    return 'Znikające · $duration';
  }

  @override
  String disappearingComposerBannerSemantics(String duration) {
    return 'Znikające wiadomości, $duration';
  }

  @override
  String conversationDisappearingTimerHint(String duration) {
    return 'Znikające wiadomości: $duration';
  }

  @override
  String get conversationLastMessageEphemeralPreRead => 'Znika po odczytaniu';

  @override
  String conversationLastMessageEphemeralRemaining(String duration) {
    return 'Znika za $duration';
  }

  @override
  String get disappearingTimerDaysLabel => 'Dni';

  @override
  String get disappearingTimerHoursLabel => 'Godziny';

  @override
  String get disappearingTimerMinutesLabel => 'Minuty';

  @override
  String get disappearingTimerSecondsLabel => 'Sekundy';

  @override
  String get disappearingTimerApply => 'Zastosuj';

  @override
  String get disappearingTimerOff => 'Wyłączone';

  @override
  String get disappearingTimerOutOfRange =>
      'Timer: od 5 sekund do 30 dni albo same zera, aby wyłączyć.';

  @override
  String disappearingTimerDays(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dnia',
      many: '$count dni',
      few: '$count dni',
      one: '1 dzień',
    );
    return '$_temp0';
  }

  @override
  String disappearingTimerHours(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count godziny',
      many: '$count godzin',
      few: '$count godziny',
      one: '1 godzina',
    );
    return '$_temp0';
  }

  @override
  String disappearingTimerMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minuty',
      many: '$count minut',
      few: '$count minuty',
      one: '1 minuta',
    );
    return '$_temp0';
  }

  @override
  String disappearingTimerSeconds(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sekundy',
      many: '$count sekund',
      few: '$count sekundy',
      one: '1 sekunda',
    );
    return '$_temp0';
  }

  @override
  String get actionTileGif => 'GIF';

  @override
  String get actionTileAntiQuantumNote => 'Notatka antykwantowa';

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

  @override
  String get gifNoResults => 'Nie znaleziono GIFów';

  @override
  String get gifSearchHint => 'Szukaj GIFów...';

  @override
  String get gifLoadError => 'Nie udało się załadować GIFów';

  @override
  String get antiQuantumNoteTitle => 'Notatka antykwantowa';

  @override
  String get antiQuantumNoteHint => 'Napisz swoją tajną wiadomość...';

  @override
  String get antiQuantumNoteTtl1h => '1h';

  @override
  String get antiQuantumNoteTtl6h => '6h';

  @override
  String get antiQuantumNoteTtl12h => '12h';

  @override
  String get antiQuantumNoteTtl24h => '24h';

  @override
  String get antiQuantumNoteGenerateAndSend => '🔗 Wygeneruj i wyślij';

  @override
  String get antiQuantumNoteFooter =>
      'Szyfrowanie po stronie klienta · Klucz nigdy nie opuszcza Twojego urządzenia';

  @override
  String get antiQuantumNoteSent => 'Notatka antykwantowa wysłana';

  @override
  String antiQuantumNoteSendFailed(String error) {
    return 'Nie udało się wysłać notatki: $error';
  }

  @override
  String get antiQuantumNoteCardSubtitle =>
      'Jednorazowy odczyt · Dotknij, aby otworzyć';

  @override
  String antiQuantumNoteCardCountdown(String time) {
    return 'Zniszczy się za $time';
  }

  @override
  String get antiQuantumNoteCardDestroyed =>
      'Ta notatka uległa samozniszczeniu';

  @override
  String get privacyAntiQuantumNoteTitle => 'Notatki antykwantowe';

  @override
  String get privacyAntiQuantumNoteDescription =>
      'Notatki są szyfrowane na Twoim urządzeniu przed wysłaniem — serwer przechowuje wyłącznie nieczytelny szyfrogram, a klucz deszyfrujący podróżuje jedynie we fragmencie linku (#), którego przeglądarki nigdy nie wysyłają do żadnego serwera. Notatkę można odczytać dokładnie raz, po czym jest trwale usuwana. Nieotwarte notatki niszczą się same po upływie timera (1h–24h), a wiadomość w czacie znika razem z nimi.';

  @override
  String get documentDownloaded => 'Dokument pobrany';

  @override
  String get documentDownloadFailed => 'Nie udało się pobrać dokumentu';

  @override
  String get documentDownloadConfirmTitle => 'Pobrać dokument?';

  @override
  String get documentDownloadConfirmMessage => 'Czy chcesz pobrać ten plik?';

  @override
  String get download => 'Pobierz';

  @override
  String get snackbarCouldNotReadFile => 'Nie udało się odczytać pliku';

  @override
  String get snackbarUploadingImage => 'Wysyłanie zdjęcia…';

  @override
  String get snackbarImageSent => 'Zdjęcie wysłane!';

  @override
  String get snackbarUploadingDocument => 'Wysyłanie dokumentu…';

  @override
  String get snackbarDocumentSent => 'Dokument wysłany!';

  @override
  String get snackbarNoActiveConversation => 'Brak aktywnej rozmowy';

  @override
  String get snackbarOpenConversationFirst => 'Najpierw otwórz rozmowę';

  @override
  String get snackbarChatHistoryDeleted => 'Historia czatu została usunięta';

  @override
  String get snackbarFailedToSendImage => 'Nie udało się wysłać zdjęcia';

  @override
  String get snackbarMicrophonePermissionRequired =>
      'Wymagane jest uprawnienie do mikrofonu';

  @override
  String get snackbarMicrophonePermissionDenied =>
      'Odmowa dostępu do mikrofonu';

  @override
  String get snackbarNoMicrophoneFound => 'Nie znaleziono mikrofonu';

  @override
  String get snackbarVoiceRecordingRequiresSecureContext =>
      'Nagrywanie głosu wymaga HTTPS lub localhost. Użyj https:// lub otwórz z localhost.';

  @override
  String get snackbarFailedToStartRecording =>
      'Nie udało się rozpocząć nagrywania';

  @override
  String get snackbarVoiceRecordingCanceled => 'Nagrywanie głosu anulowane';

  @override
  String get voiceRecordingSendVoiceTooltip => 'Wyślij wiadomość głosową';

  @override
  String get voiceRecordingSendVoiceSemantics => 'Wyślij wiadomość głosową';

  @override
  String get voiceRecordingDiscard => 'Odrzuć nagranie';

  @override
  String voiceRecordingSemanticsLabel(String time) {
    return 'Nagrywanie wiadomości głosowej, $time.';
  }

  @override
  String get snackbarFailedToReadRecording => 'Nie udało się odczytać nagrania';

  @override
  String get snackbarFailedToSendVoiceMessage =>
      'Nie udało się wysłać wiadomości głosowej';

  @override
  String get snackbarAudioNoLongerAvailable => 'Dźwięk nie jest już dostępny';

  @override
  String get snackbarFailedToLoadAudio => 'Nie udało się wczytać dźwięku';

  @override
  String get snackbarLocalMessageCacheCleared =>
      'Lokalna pamięć wiadomości wyczyszczona';

  @override
  String get snackbarFailedToClearLocalMessageCache =>
      'Nie udało się wyczyścić lokalnej pamięci wiadomości';

  @override
  String friendAcceptedYourRequest(String name) {
    return '$name zaakceptował(a) zaproszenie do znajomych';
  }

  @override
  String get themeOptionLight => 'Ciepły papier (jasny)';

  @override
  String get themeOptionDark => 'Ciemny szary z turkusowym akcentem';

  @override
  String get themeOptionBlue => 'Niebieski w stylu Telegram (ciemny)';

  @override
  String get themeOptionTealStone => 'Turkus i kamień (nowoczesny jasny)';

  @override
  String get rotateDeviceTitle => 'Obróć urządzenie';

  @override
  String get rotateDeviceMessage => 'Fireplace działa tylko w trybie pionowym.';

  @override
  String get messageActionReply => 'Odpowiedz';

  @override
  String get messageActionCopy => 'Kopiuj';

  @override
  String get messageActionEdit => 'Edytuj';

  @override
  String get messageActionPin => 'Przypnij';

  @override
  String get messageActionDelete => 'Usuń';

  @override
  String get messageDeleteDialogTitle => 'Usunąć wiadomość?';

  @override
  String get messageDeleteForMe => 'Usuń u mnie';

  @override
  String get messageDeleteForEveryone => 'Usuń dla wszystkich';

  @override
  String get messageEditedLabel => 'edytowano';

  @override
  String get messageEditingTitle => 'Edytowanie wiadomości';

  @override
  String get messagePinRequiresSentMessage =>
      'Poczekaj na wysłanie wiadomości, aby ją przypiąć';

  @override
  String get messageReactionMoreEmoji => 'Więcej reakcji emoji';

  @override
  String get messageReactionSelected => 'wybrana';

  @override
  String get messageReactionNotSelected => 'niewybrana';

  @override
  String messageReactionSemantics(Object emoji, Object state) {
    return 'Reakcja $emoji, $state';
  }

  @override
  String get snackbarPinnedMessageUnavailable => 'Wiadomość jest niedostępna';

  @override
  String get snackbarMessageCopied => 'Skopiowano wiadomość';

  @override
  String get composerAttachmentRemoveTooltip => 'Usuń załącznik';

  @override
  String get snackbarPastedImageTooLarge => 'Obraz jest za duży (maks. 20 MB)';

  @override
  String get snackbarPastedImageUnsupported =>
      'Nie można wkleić tego typu obrazu';

  @override
  String get snackbarPastedImageUnavailable =>
      'Nie udało się odczytać wklejonego obrazu';

  @override
  String get pinnedMessageUnpinTooltip => 'Odepnij';

  @override
  String get pinnedMessageBannerSemantics => 'Przypięta wiadomość';
}
