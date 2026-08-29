// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

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
      'Najpierw dodaj Umbra do ekranu głównego (Safari -> Udostępnij -> Do ekranu początkowego)';

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
  String get uploadFailed => 'Nie udało się przesłać';

  @override
  String get passwordUpdatedSuccessfully => 'Hasło zostało zmienione';

  @override
  String get passwordResetFailed => 'Nie udało się zmienić hasła';

  @override
  String get accountDeletionFailed => 'Nie udało się usunąć konta';

  @override
  String get devicesLoading => 'Ładowanie…';

  @override
  String get devicesExplainer =>
      'Urządzenia połączone z tym kontem. Nowe urządzenie można dodać tylko z tego, głównego urządzenia.';

  @override
  String get devicesNotEnrolled =>
      'Łączenie urządzeń nie jest jeszcze włączone dla tego konta.';

  @override
  String get devicesEnableLinking => 'Włącz łączenie';

  @override
  String get devicesLinkADevice => 'Połącz urządzenie';

  @override
  String get devicesLinkThisDevice => 'Połącz to urządzenie';

  @override
  String get devicesAlreadyEnrolled =>
      'Inna instalacja tego konta już włączyła łączenie. Urządzenia można dodawać tylko z tamtego urządzenia.';

  @override
  String get devicesEnrollFailed =>
      'Nie udało się włączyć łączenia. Spróbuj ponownie.';

  @override
  String get devicesChainInvalid =>
      'Nie można zweryfikować listy urządzeń. Spróbuj ponownie później.';

  @override
  String get devicesRevokedBadge => 'cofnięte';

  @override
  String get devicesRevokeAction => 'Usuń urządzenie';

  @override
  String get devicesRevokeTitle => 'Usunąć to urządzenie?';

  @override
  String get devicesRevokeExplainer =>
      'Zostanie wylogowane i przestanie odbierać nowe wiadomości. Wiadomości już zapisane na tym urządzeniu nie zostaną usunięte.';

  @override
  String get devicesRevokeFailed =>
      'Nie udało się usunąć tego urządzenia. Spróbuj ponownie.';

  @override
  String get deviceRevokedNotice =>
      'To urządzenie zostało usunięte z Twojego konta. Twoje wiadomości na nim pozostały — zaloguj się ponownie, aby pisać dalej.';

  @override
  String get devicesPrimaryBadge => 'główne';

  @override
  String get devicesThisDeviceKeyless =>
      'To urządzenie nie ma jeszcze kluczy. Połącz je ze swoim głównym urządzeniem.';

  @override
  String get linkPrimaryTitle => 'Połącz urządzenie';

  @override
  String get linkPrimaryExplainer =>
      'Na nowym urządzeniu wybierz „Połącz to urządzenie”, a potem wpisz tutaj wyświetlony kod.';

  @override
  String get linkPrimaryCodeLabel => 'Kod z nowego urządzenia';

  @override
  String get linkPrimaryContinue => 'Dalej';

  @override
  String get linkSasHeading => 'Porównaj kody';

  @override
  String get linkSasExplainer =>
      'Oba urządzenia muszą pokazywać ten sam kod. Zatwierdź tylko wtedy, gdy są identyczne.';

  @override
  String get linkApprove => 'Zatwierdź';

  @override
  String get linkCancel => 'Anuluj';

  @override
  String get linkWaitingForDevice => 'Czekam na nowe urządzenie…';

  @override
  String get linkPrimaryDone => 'Urządzenie zostało połączone.';

  @override
  String get linkInvalidCode =>
      'Nieprawidłowy kod. Przepisz go dokładnie z nowego urządzenia.';

  @override
  String get linkNoDak =>
      'Brak klucza autoryzacji na tym urządzeniu. Łączyć można tylko z urządzenia, które włączyło łączenie.';

  @override
  String get linkFailed => 'Łączenie nie powiodło się';

  @override
  String get linkStaleVersionRetry =>
      'Lista urządzeń zmieniła się w trakcie — podpisuję ponownie…';

  @override
  String get linkNewTitle => 'Połącz to urządzenie';

  @override
  String get linkNewExplainer =>
      'Pokaż ten kod na głównym urządzeniu: wybierz tam „Połącz urządzenie” i przepisz kod (albo zeskanuj QR).';

  @override
  String get linkNewWaitingHello => 'Czekam na główne urządzenie…';

  @override
  String get linkNewCopy => 'Skopiuj kod';

  @override
  String get linkNewCopied => 'Kod skopiowany';

  @override
  String get linkNewCompleting => 'Łączenie…';

  @override
  String get linkNewRebinding => 'Przełączam sesję na nowe urządzenie…';

  @override
  String get linkNewDone => 'To urządzenie jest połączone i gotowe.';

  @override
  String get linkNewAborted => 'Łączenie przerwane';

  @override
  String get linkNewRetry => 'Spróbuj ponownie';

  @override
  String get linkAbortReasonExpired => 'Kod wygasł.';

  @override
  String get linkAbortReasonCancelled =>
      'Łączenie anulowano na drugim urządzeniu.';

  @override
  String get linkAbortReasonBadBlob =>
      'Weryfikacja danych nie powiodła się. Klucze zostały usunięte z tego urządzenia.';

  @override
  String get settingsAppVersion => 'Wersja aplikacji';

  @override
  String get settingsAboutFireplace => 'O projekcie';

  @override
  String get settingsSectionPreferences => 'PREFERENCJE';

  @override
  String get settingsSectionSecurity => 'BEZPIECZEŃSTWO';

  @override
  String get settingsSectionSession => 'SESJA';

  @override
  String get privacySafetyTitle => 'Prywatność i bezpieczeństwo';

  @override
  String get e2eEncryptionEnabled => 'Szyfrowanie end-to-end jest włączone';

  @override
  String get e2eEncryptionDescription =>
      'Twoje wiadomości są szyfrowane protokołem Signal. Tylko Ty i odbiorca możecie je odczytać. Serwery Umbra nie mają dostępu do treści wiadomości.';

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
  String get deleteAllLocalHistoryTitle =>
      'Usuń wszystkie wiadomości z tego urządzenia';

  @override
  String get deleteAllLocalHistoryDescription =>
      'Trwale usuwa z tego urządzenia wszystkie zapisane wiadomości, w tym pobrane notatki głosowe. Nie usuwa konta, wiadomości z urządzenia drugiej osoby ani kluczy i sesji szyfrowania. Tej operacji nie można cofnąć: serwer przechowywał wyłącznie zaszyfrowane dane, których nie potrafi odczytać, więc nie ma kopii do przywrócenia.';

  @override
  String get deleteAllLocalHistoryButton =>
      'Usuń trwale wszystkie lokalne wiadomości';

  @override
  String get deleteAllLocalHistoryDialogTitle =>
      'Trwale usunąć wszystkie lokalne wiadomości?';

  @override
  String get deleteAllLocalHistoryDialogBody =>
      'Ta operacja trwale usuwa z tego urządzenia wszystkie wiadomości i pobrane notatki głosowe. Nie można jej cofnąć — serwer przechowywał wyłącznie zaszyfrowane dane, których nie potrafi odczytać, więc nie ma kopii do przywrócenia. Twoje konto, klucze i sesje szyfrowania pozostaną bez zmian.';

  @override
  String get deleteAllLocalHistoryConfirm => 'Usuń trwale';

  @override
  String get yourIdentityFingerprint => 'Twój odcisk tożsamości';

  @override
  String get shareFingerprintHint =>
      'To unikalna reprezentacja Twojego klucza szyfrowania.';

  @override
  String get invitations => 'Zaproszenia';

  @override
  String get invitationsWaitingForYou => 'Czeka na Ciebie';

  @override
  String get invitationsSent => 'Wysłane';

  @override
  String get invitationsNothingWaiting => 'Nic na Ciebie nie czeka';

  @override
  String get invitationsNoneSent => 'Brak wysłanych zaproszeń';

  @override
  String get inviteByHandleHint =>
      'Zaproś kogoś po username#tag. Swój #tag znajdziesz w Ustawieniach przy nicku.';

  @override
  String get usernameTagPlaceholder => 'username#1234';

  @override
  String get sendInvitation => 'Wyślij zaproszenie';

  @override
  String get invitationFindUser => 'Znajdź użytkownika';

  @override
  String get userNotFound => 'Nie znaleziono użytkownika';

  @override
  String get invitationWantsToConnect => 'Chce się połączyć';

  @override
  String get invitationWaitingForResponse => 'Czeka na odpowiedź';

  @override
  String get invitationAccepted => 'Zaproszenie zaakceptowane';

  @override
  String get invitationChatReady => 'Czat gotowy';

  @override
  String get invitationChatNeedsRetry => 'Czat wymaga ponowienia';

  @override
  String get invitationOpenChat => 'Otwórz czat';

  @override
  String get invitationCreateChat => 'Utwórz czat';

  @override
  String get invitationDone => 'Gotowe';

  @override
  String get invitationDecline => 'Odrzuć';

  @override
  String get accept => 'Zaakceptuj';

  @override
  String get invitationStatusPending => 'Oczekuje';

  @override
  String get invitationSendFailed => 'Nie udało się wysłać zaproszenia';

  @override
  String get invitationAcceptFailed => 'Nie udało się zaakceptować zaproszenia';

  @override
  String get invitationDeclineFailed => 'Nie udało się odrzucić zaproszenia';

  @override
  String get invitationChatSetupFailed => 'Nie udało się utworzyć czatu';

  @override
  String get invitationFailedUserNotFound => 'Ten użytkownik już nie istnieje';

  @override
  String get invitationFailedSelf => 'Nie możesz zaprosić samego siebie';

  @override
  String get invitationFailedBlocked => 'Nie możesz zaprosić tego użytkownika';

  @override
  String get invitationFailedAlreadyFriends => 'Już jesteście połączeni';

  @override
  String get invitationFailedDuplicate => 'Zaproszenie zostało już wysłane';

  @override
  String get invitationFailedInvalidPayload =>
      'Coś było nie tak z tym żądaniem';

  @override
  String get invitationFailedNotFriends =>
      'Nie jesteś połączony z tym użytkownikiem';

  @override
  String invitationSemanticIncoming(String name) {
    return '$name, otrzymane zaproszenie, chce się połączyć';
  }

  @override
  String invitationSemanticOutgoing(String name) {
    return '$name, wysłane zaproszenie, czeka na odpowiedź';
  }

  @override
  String invitationSemanticAcceptedReady(String name) {
    return '$name, zaproszenie zaakceptowane, czat gotowy';
  }

  @override
  String invitationSemanticAcceptedNotReady(String name) {
    return '$name, zaproszenie zaakceptowane, czat wymaga ponowienia';
  }

  @override
  String get encryptedMessage => 'Wiadomość zaszyfrowana';

  @override
  String get decryptionFailed => 'Odszyfrowanie nie powiodło się';

  @override
  String get decryptingMessage => 'Odszyfrowywanie…';

  @override
  String get messageNoLongerStoredOnThisDevice =>
      'Ta wiadomość nie jest już przechowywana na tym urządzeniu.';

  @override
  String get messageSentBeforeDeviceLinked =>
      'Wysłana przed połączeniem tego urządzenia.';

  @override
  String get devicesSyncingNote => 'Synchronizowanie urządzeń…';

  @override
  String get encryptionNotInitialized => 'Szyfrowanie niezainicjowane';

  @override
  String get identityDamagedTitle =>
      'Brak kluczy szyfrowania na tym urządzeniu';

  @override
  String get identityDamagedBody =>
      'Logujesz się na nowym urządzeniu lub w nowej przeglądarce? Twoje konto ma już klucze szyfrowania gdzie indziej, a to urządzenie ich nie ma. Jeśli to Twoje dotychczasowe urządzenie, zapisane klucze zostały utracone. Tak czy inaczej nic nie zostało odtworzone automatycznie — zrobienie tego po cichu zniszczyłoby możliwość odczytania historii.';

  @override
  String get identityDamagedAction => 'Zacznij od nowa';

  @override
  String get identityDamagedConfirmTitle => 'Utworzyć nowe klucze?';

  @override
  String get identityDamagedConfirmBody =>
      'Zostanie utworzona nowa tożsamość, a kontakty automatycznie wymienią klucze. Wiadomości już otwarte na tym urządzeniu pozostaną czytelne. Wiadomości, których to urządzenie nigdy nie odszyfrowało, będą nie do odzyskania.';

  @override
  String get identityDamagedConfirmAction => 'Utwórz nowe klucze';

  @override
  String get peerIdentityMarkVerifiedAction => 'Odciski się zgadzają';

  @override
  String get peerIdentityVerifyMenuAction => 'Zweryfikuj klucze bezpieczeństwa';

  @override
  String get peerIdentityFingerprintDialogTitle =>
      'Zweryfikuj klucze bezpieczeństwa';

  @override
  String peerIdentityFingerprintDialogDescription(String name) {
    return 'Porównaj te odciski z użytkownikiem $name za pośrednictwem innego kanału. Muszą być identyczne.';
  }

  @override
  String peerIdentityFingerprintPeerLabel(String name) {
    return 'Odcisk tożsamości użytkownika $name';
  }

  @override
  String get peerIdentityFingerprintNoStoredKey =>
      'Brak zapisanego klucza tożsamości dla tego kontaktu.';

  @override
  String peerIdentityFingerprintChangedNotice(String name) {
    return 'Klucze użytkownika $name uległy zmianie. Porównaj NOWY odcisk poniżej — poprzedni pokazujemy tylko po to, aby było widać, co się zmieniło.';
  }

  @override
  String peerIdentityFingerprintServedNotice(String name) {
    return 'Ten klucz pochodzi z serwera i żadna wiadomość od użytkownika $name go jeszcze nie potwierdziła. Porównanie go innym kanałem to jedyne zabezpieczenie.';
  }

  @override
  String peerIdentityFingerprintNewLabel(String name) {
    return 'Nowy odcisk tożsamości użytkownika $name';
  }

  @override
  String get peerIdentityFingerprintPreviousLabel =>
      'Poprzednio zaufany odcisk';

  @override
  String peerIdentityFingerprintUnchangedNotice(String name) {
    return 'Klucz użytkownika $name nie zmienił się od czasu, gdy go zaakceptowałeś. Potwierdź poniżej, aby zamknąć to ostrzeżenie.';
  }

  @override
  String peerIdentityFingerprintOfferUnavailable(String name) {
    return 'Nie udało się wczytać aktualnego klucza użytkownika $name, więc nie ma jeszcze czego porównywać. Sprawdź połączenie i otwórz to ponownie.';
  }

  @override
  String peerIdentityChangedTimelineRow(String name) {
    return 'Klucze bezpieczeństwa $name uległy zmianie — zwykle to logowanie z nowego urządzenia lub przeglądarki. Dotknij, aby zweryfikować.';
  }

  @override
  String get ownIdentityReplacedTitle =>
      'Nowe klucze szyfrowania na Twoim koncie';

  @override
  String get ownIdentityReplacedBody =>
      'Inne logowanie przesłało nowe klucze szyfrowania dla Twojego konta — zwykle to nowe urządzenie, przeglądarka lub ponowna instalacja. Jeśli to nie Ty, natychmiast zmień hasło.';

  @override
  String get ownIdentityReplacedDismissAction => 'Rozumiem';

  @override
  String get identityResetPendingTitle =>
      'Ktoś poprosił o zresetowanie Twoich kluczy szyfrowania';

  @override
  String identityResetPendingBody(String remaining) {
    return 'Jeśli to nie Ty, anuluj teraz — w przeciwnym razie za $remaining Twoje konto otrzyma nowe klucze szyfrowania, a historia wiadomości stanie się nieczytelna.';
  }

  @override
  String get identityResetCancelAction => 'Anuluj';

  @override
  String identityResetHoursLeft(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours godzin',
      few: '$hours godziny',
      one: '1 godzinę',
    );
    return '$_temp0';
  }

  @override
  String identityResetMinutesLeft(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minut',
      few: '$minutes minuty',
      one: '1 minutę',
      zero: 'niecałą minutę',
    );
    return '$_temp0';
  }

  @override
  String get identityResetAnyMoment => 'lada chwila';

  @override
  String get identityUploadLockedTitle =>
      'Twoje nowe klucze szyfrowania nie zostały opublikowane';

  @override
  String get identityUploadLockedBody =>
      'To urządzenie utworzyło nowe klucze, ale konto nadal używa poprzednich, więc inne osoby nie mogą się z Tobą bezpiecznie skontaktować. Rozpocznij reset, aby opublikować te klucze — trwa 72 godziny, a wszystkie zalogowane sesje otrzymają powiadomienie.';

  @override
  String get identityResetStartAction => 'Rozpocznij reset';

  @override
  String get recoveryKeyTitle => 'Klucz odzyskiwania';

  @override
  String get recoveryKeySubtitle => 'Szybszy powrót, jeśli stracisz klucze';

  @override
  String get recoveryKeyExplainer =>
      'Jeśli kiedykolwiek stracisz dostęp do swoich kluczy szyfrowania, uzyskanie nowych trwa 72 godziny — to celowe opóźnienie, dzięki któremu nikt inny nie przejmie po cichu Twojego konta, zanim zdążysz zareagować. Klucz odzyskiwania skraca to oczekiwanie do 1 godziny. Nigdy go nie pomija, a wszystkie zalogowane sesje i tak otrzymają powiadomienie.\n\nSłowa pokazujemy tylko raz i nie zapisujemy ich na tym urządzeniu — przechowywanie ich tutaj oznaczałoby utratę dokładnie wtedy, gdy są potrzebne. Zapisz je w bezpiecznym miejscu, poza urządzeniem.';

  @override
  String get recoveryKeyGenerateAction => 'Wygeneruj klucz odzyskiwania';

  @override
  String get recoveryKeyShownOnceWarning =>
      'Te słowa pokazujemy tylko raz. Zapisz je, zanim przejdziesz dalej — wygenerowanie nowego klucza zastąpi ten.';

  @override
  String get recoveryKeyCopyAction => 'Kopiuj słowa';

  @override
  String get recoveryKeyCopied => 'Skopiowano klucz odzyskiwania';

  @override
  String get recoveryKeySavedAction => 'Zapisałem/am';

  @override
  String get recoveryKeySaved => 'Zapisano klucz odzyskiwania';

  @override
  String get recoveryKeySaveFailed =>
      'Nie udało się zapisać klucza odzyskiwania — nic nie zostało zapisane, więc te słowa nie zadziałają. Spróbuj ponownie.';

  @override
  String get recoveryPhrasePromptTitle => 'Masz klucz odzyskiwania?';

  @override
  String get recoveryPhrasePromptBody =>
      'Wpisanie 12 słów skraca oczekiwanie z 72 godzin do 1. Tak czy inaczej wszystkie zalogowane sesje otrzymają powiadomienie, a reset nadal można anulować.';

  @override
  String get recoveryPhrasePromptHint => 'dwanaście słów oddzielonych spacjami';

  @override
  String get recoveryPhraseMalformed =>
      'To nie wygląda na kompletny 12-słowny klucz odzyskiwania. Sprawdź literówki.';

  @override
  String get recoveryPhraseUseAction => 'Użyj klucza';

  @override
  String get recoveryPhraseNoneAction => 'Nie mam go';

  @override
  String get identityResetStarted =>
      'Reset rozpoczęty. Wszystkie zalogowane sesje zostały powiadomione, a do końca odliczania można go anulować.';

  @override
  String get identityResetPhraseTooNew =>
      'Reset rozpoczęty. Twój klucz odzyskiwania był poprawny, ale został utworzony mniej niż 3 dni temu, więc tym razem nie może skrócić oczekiwania — obowiązują pełne 72 godziny. Nie musisz wpisywać go ponownie.';

  @override
  String get identityResetAlreadyRunning =>
      'Dla tego konta reset już trwa. Odliczanie na górze ekranu pokazuje, ile zostało czasu.';

  @override
  String get identityResetCooldown =>
      'Reset został niedawno anulowany, więc nowy nie może ruszyć przez maksymalnie 24 godziny. Jeśli ktoś inny wciąż go anuluje, najpierw zmień hasło, aby go wylogować.';

  @override
  String get identityResetPhraseRejected =>
      'Te 12 słów nie pasuje do klucza odzyskiwania zapisanego dla tego konta. Możesz spróbować ponownie albo rozpocząć reset bez klucza i poczekać 72 godziny.';

  @override
  String get identityResetPhraseLocked =>
      'Zbyt wiele prób z kluczem odzyskiwania. Spróbuj ponownie za około godzinę albo rozpocznij reset bez klucza i poczekaj 72 godziny.';

  @override
  String get identityResetNoAnswer =>
      'Brak odpowiedzi serwera, więc nic nie zostało rozpoczęte. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get identityFingerprintUnavailable =>
      'Odcisk tożsamości jest niedostępny.';

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
  String get attachmentOptionDocument => 'Dokument';

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
  String get contactNetworkLocalNode => 'WĘZEŁ LOKALNY';

  @override
  String get contactNetworkYouLocalNode => 'Ty, węzeł lokalny';

  @override
  String contactNetworkSemantic(num count) {
    return 'Sieć kontaktów, $count kontaktów';
  }

  @override
  String contactNetworkNodes(String count) {
    return 'WĘZŁY $count';
  }

  @override
  String get contactNetworkShowList => 'Widok listy';

  @override
  String get contactNetworkShowMap => 'Widok sieci';

  @override
  String get contactNetworkOpenChatHint => 'Otwórz czat';

  @override
  String get contactNetworkAddSlot => 'dodaj';

  @override
  String get contactNetworkAddSlotSemantic => 'Dodaj kontakt';

  @override
  String contactNetworkPendingRequests(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zaproszeń oczekuje',
      many: '$count zaproszeń oczekuje',
      few: '$count zaproszenia oczekują',
      one: '1 zaproszenie oczekuje',
    );
    return '$_temp0';
  }

  @override
  String get contactsSearchHint => 'Szukaj kontaktów';

  @override
  String get contactsSearchNoResults => 'Brak pasujących kontaktów';

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
  String sessionEndedReason(String reason) {
    return 'wylogowano: $reason';
  }

  @override
  String get authTagline => 'Wiadomości, które przeczytają tylko dwie osoby';

  @override
  String get authLoginTab => 'LOGOWANIE';

  @override
  String get authRegisterTab => 'REJESTRACJA';

  @override
  String get authUsernameHint => 'Nazwa użytkownika';

  @override
  String get authUsernameRequired => 'Nazwa użytkownika jest wymagana';

  @override
  String get authPasswordHint => 'Hasło';

  @override
  String get authPasswordHintRegister => 'Hasło (min. 8 znaków)';

  @override
  String get authLoginButton => 'Zaloguj się';

  @override
  String get authCreateAccountButton => 'Utwórz konto';

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
  String get antiQuantumNoteBurnedTitle => 'Notatka zniszczona';

  @override
  String get antiQuantumNoteBurnedSubtitle => 'została odczytana';

  @override
  String get antiQuantumNoteRevealWarning =>
      'Tę notatkę można odczytać tylko raz. Odsłonięcie zniszczy ją trwale — dla wszystkich, na zawsze.';

  @override
  String get antiQuantumNoteRevealConfirm => 'Odsłoń i zniszcz';

  @override
  String get antiQuantumNoteRevealLoading => 'Odszyfrowywanie…';

  @override
  String get antiQuantumNoteRevealedHeader =>
      'Wiadomość odsłonięta · trwale zniszczona';

  @override
  String get antiQuantumNoteRevealedFooter =>
      'Notatka została usunięta z serwera. Widać ją już tylko na tym ekranie.';

  @override
  String get antiQuantumNoteRevealClose => 'Zamknij';

  @override
  String get antiQuantumNoteRevealRetry => 'Spróbuj ponownie';

  @override
  String get antiQuantumNoteRevealDestroyedBody =>
      'Ta notatka została już odczytana i zniszczona. Nie da się jej przywrócić.';

  @override
  String get antiQuantumNoteRevealExpiredTitle => 'Notatka wygasła';

  @override
  String get antiQuantumNoteRevealExpiredBody =>
      'Ta notatka wygasła i zniszczyła się, zanim została odczytana.';

  @override
  String get antiQuantumNoteRevealCorruptBody =>
      'Notatka została zniszczona, ale nie udało się jej odszyfrować. Link może być uszkodzony.';

  @override
  String get antiQuantumNoteRevealInvalidLinkTitle => 'Uszkodzony link';

  @override
  String get antiQuantumNoteRevealInvalidLinkBody =>
      'W tym linku brakuje prawidłowego klucza deszyfrującego. Notatka nie została zniszczona.';

  @override
  String get antiQuantumNoteRevealNetworkErrorTitle => 'Brak połączenia';

  @override
  String get antiQuantumNoteRevealNetworkErrorBody =>
      'Nie udało się połączyć z serwerem. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get privacyAntiQuantumNoteTitle => 'Notatki antykwantowe';

  @override
  String get privacyAntiQuantumNoteLead =>
      'Samoniszczące wiadomości z własną, drugą warstwą szyfrowania — nawet link nie zdradza sekretu.';

  @override
  String get privacyAntiQuantumNotePointDevice =>
      'Szyfrowane na Twoim urządzeniu przed wysłaniem — serwer przechowuje wyłącznie nieczytelny szyfrogram.';

  @override
  String get privacyAntiQuantumNotePointKey =>
      'Klucz deszyfrujący podróżuje jedynie we fragmencie linku (#), którego przeglądarki nigdy nie wysyłają do żadnego serwera.';

  @override
  String get privacyAntiQuantumNotePointOnce =>
      'Notatkę można odczytać dokładnie raz — po czym jest trwale usuwana.';

  @override
  String get privacyAntiQuantumNotePointTimer =>
      'Nieotwarte notatki niszczą się same po upływie timera (1h–24h), a wiadomość w czacie znika razem z nimi.';

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
  String get saveImage => 'Zapisz obraz';

  @override
  String get copyImage => 'Kopiuj obraz';

  @override
  String get imageSaved => 'Zapisano obraz';

  @override
  String get imageSaveFailed => 'Nie udało się zapisać obrazu';

  @override
  String get imageCopied => 'Skopiowano obraz';

  @override
  String get imageCopyFailed => 'Nie udało się skopiować obrazu';

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
  String get messageTooLong => 'Wiadomość jest za długa, aby ją wysłać';

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
  String get snackbarAllLocalHistoryDeleted =>
      'Wszystkie wiadomości zapisane na tym urządzeniu zostały trwale usunięte';

  @override
  String get snackbarFailedToDeleteAllLocalHistory =>
      'Nie udało się usunąć części wiadomości z tego urządzenia. Spróbuj ponownie.';

  @override
  String friendAcceptedYourRequest(String name) {
    return '$name zaakceptował(a) zaproszenie do znajomych';
  }

  @override
  String get appearance => 'Wygląd';

  @override
  String appearanceSummary(String theme, String background) {
    return '$theme · $background';
  }

  @override
  String get appearanceColorTheme => 'MOTYW KOLORYSTYCZNY';

  @override
  String get appearanceThemeLight => 'Alabaster';

  @override
  String get appearanceThemeTeal => 'Turkus';

  @override
  String get appearanceThemeDark => 'Grafit';

  @override
  String get appearanceThemeBlue => 'Błękit';

  @override
  String get appearanceThemeCosmic => 'Kosmos';

  @override
  String get themeOptionLight => 'Jasny ciepły papier z żarowymi akcentami';

  @override
  String get themeOptionDark =>
      'Ciemny neutralny grafit z turkusowymi akcentami';

  @override
  String get themeOptionBlue => 'Głęboki granat z błękitnymi akcentami';

  @override
  String get themeOptionTealStone =>
      'Jasny chłodny kamień z turkusowymi akcentami';

  @override
  String get themeOptionCosmic => 'Ciemny kosmos z lodowoniebieskim światłem';

  @override
  String get appearanceChatBackground => 'TŁO CZATU';

  @override
  String get appearanceBackgroundThemeDefault => 'Domyślne motywu';

  @override
  String get appearanceBackgroundThemeDefaultSubtitle =>
      'Dopasowuje się do wybranego motywu';

  @override
  String get appearanceBackgroundThemeDefaultCosmicSubtitle =>
      'Animowane gwiazdy dla motywu Kosmos';

  @override
  String get appearanceBackgroundPlain => 'Gładkie';

  @override
  String get appearanceBackgroundPlainSubtitle =>
      'Jednolite tło w kolorach motywu';

  @override
  String get appearanceBackgroundGlyphs => 'Hieroglify';

  @override
  String get appearanceBackgroundGlyphsSubtitle => 'Wzór świątynnych kolumn';

  @override
  String get appearanceBackgroundStarfield => 'Gwiazdy';

  @override
  String get rotateDeviceTitle => 'Obróć urządzenie';

  @override
  String get rotateDeviceMessage => 'Umbra działa tylko w trybie pionowym.';

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

  @override
  String get userCardAbout => 'O mnie';

  @override
  String get userCardMyProfile => 'Mój profil';

  @override
  String get userCardEditAbout => 'Edytuj opis';

  @override
  String get userCardAddPhoto => 'Dodaj zdjęcie';

  @override
  String get userCardPhotoLimitReached => 'Osiągnięto limit zdjęć';

  @override
  String get userCardSetMainPhoto => 'Ustaw jako główne zdjęcie';

  @override
  String get userCardDeletePhoto => 'Usuń to zdjęcie';

  @override
  String get userCardSave => 'Zapisz';

  @override
  String get userCardCancel => 'Anuluj';

  @override
  String get userCardBack => 'Wstecz';

  @override
  String get userCardNotificationsOn => 'Powiadomienia włączone';

  @override
  String get userCardMuteOneHour => 'Wycisz na 1 godzinę';

  @override
  String get userCardMuteEightHours => 'Wycisz na 8 godzin';

  @override
  String get userCardMuteOneWeek => 'Wycisz na tydzień';

  @override
  String get userCardMuteForever => 'Wycisz na zawsze';

  @override
  String get userCardMessage => 'Wiadomość';

  @override
  String get userCardMute => 'Wycisz';

  @override
  String get userCardMuted => 'Wyciszono';

  @override
  String get userCardCopyTag => 'Kopiuj tag';

  @override
  String get userCardManagePhotos => 'Zarządzaj zdjęciami';

  @override
  String userCardPhotoOfCount(Object index, Object count) {
    return 'Zdjęcie $index z $count';
  }

  @override
  String get userCardMainPhotoHint =>
      'To jest Twoje główne zdjęcie — kontakty widzą je na czatach.';

  @override
  String get userCardAboutHint => 'Kilka słów o Tobie';

  @override
  String get userCardSharedMedia => 'Udostępnione multimedia';

  @override
  String get userCardDragReorderHint =>
      'Przytrzymaj i przeciągnij, aby zmienić kolejność — pierwsze zdjęcie jest Twoim głównym.';

  @override
  String get settingsChatBackground => 'Tło czatu';

  @override
  String get userCardCopyHandle => 'Kopiuj nazwę użytkownika i tag';

  @override
  String userCardCopiedHandle(Object handle) {
    return 'Skopiowano $handle';
  }

  @override
  String get userCardNotificationsMuted => 'Powiadomienia wyciszone';

  @override
  String userCardBlockTitle(Object handle) {
    return 'Zablokować $handle?';
  }

  @override
  String get userCardBlockConfirm =>
      'Nie będzie można wysyłać wiadomości do tego kontaktu.';

  @override
  String get userCardDeletePhotoTitle => 'Usunąć zdjęcie?';

  @override
  String get userCardDeletePhotoConfirm =>
      'To trwale usuwa to zdjęcie profilowe.';

  @override
  String get userCardSafety => 'Bezpieczeństwo';

  @override
  String get userCardRemoveContact => 'Usuń kontakt';

  @override
  String get messageReadMore => 'Czytaj więcej';

  @override
  String get messageShowLess => 'Zwiń';

  @override
  String get chatPickerTitle => 'Wybierz znajomego';

  @override
  String get chatPickerSubtitle => 'Wybierz węzeł, aby rozpocząć czat';

  @override
  String get chatPickerEmptyTitle => 'Nie masz jeszcze znajomych';

  @override
  String get chatPickerEmptyDescription =>
      'Dodaj znajomego, aby rozpocząć czat.';

  @override
  String get chatPickerOpenTooltip => 'Nowy czat';

  @override
  String get chatPickerInviteButton => 'Zaproś kogoś';

  @override
  String get videoMessage => 'Wideo';

  @override
  String get videoTooLarge => 'Wideo jest za duże (maks. 20 MB)';

  @override
  String get videoTooLong => 'Wideo jest za długie (maks. 60 sekund)';

  @override
  String get videoUnsupportedFormat =>
      'Nieobsługiwany format wideo (tylko MP4)';

  @override
  String get attachmentUnsupportedFileType => 'Nieobsługiwany typ pliku';
}
