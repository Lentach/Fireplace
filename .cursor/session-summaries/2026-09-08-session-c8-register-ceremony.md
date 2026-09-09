# 2026-09-08 (c8) — registration settles itself; text-pass proposal

**Date:** 2026-09-08 (evening, after 0.2.27)

## What was done

- **Diagnosed the friend's "server error" from prod logs, not the screenshot.** IP `31.175.148.17`, iPhone Safari (UA carries `Safari/604.1` — a browser TAB, never the installed PWA). 19:03 UTC loads the app; nothing reaches nginx for 4 minutes; 19:08:23 `login ___` ×3 (401) + `register ___` (201) arrive in the SAME second; 19:08:25 `login ___` 201 → shell, 15 min of use. Shape: iOS froze the tab's socket while he was in Telegram (the `TELEGRAM` pill), the first POST after resume hung, our 15 s timeout fired and he read `authStatusRegisterOutcomeUnknown` as an outage; everything he tapped afterwards flushed in one burst. Account `___#7868` (id 117) exists. No backend bug; `___` is a valid name (exact-match lookup, no LIKE).
- **0.2.28 (`00ee34e`, web-only):** `AuthProvider.register` settles a lost answer itself — sign in with the same credentials; a refusal proves the server is back and the account is not ours, so the register is retried ONCE (its 409 lands in the existing taken→sign-in branch); only a second lost answer is reported. `login` retries a lost answer once. `AuthStatusCode.registerOutcomeUnknown` and its two paragraphs deleted; `authStatusServerUnreachable` is now `Brak połączenia. Spróbuj ponownie.` / `No connection. Try again.` `_signIn`/`_register` return the classified code (null = success); `_report` is the single status writer for failures.
- **Text-pass proposal drafted, NOT coded** (owner reviews first): `.planning/text-pass/proposal.md` — 68 strings ≥90 chars rewritten to one line ≤70 chars PL, mechanism removed; 6 ICU plurals excluded. Pasted to the owner in chat.

## Key files

- `frontend/lib/providers/auth_provider.dart` — `register`, `login`, `_register`, `_signIn`, `_report`; `classifyAuthFailure` lost → `serverUnreachable` for every attempt.
- `frontend/lib/l10n/app_pl.arb`, `app_en.arb` (+ generated) — key removed, one shortened. `frontend/lib/l10n/auth_status_text.dart`.
- `frontend/test/providers/auth_registration_outcome_test.dart` — group `a lost register answer is settled by the provider` (5) + 2 login retry cases. `test/screens/auth_screen_theme_test.dart` mapping.

## Verification

- Mutants, 1 substitution each, restored, `git diff` clean: F25 `if (false)` on the settle branch → +13 −4; F26 report instead of retry after a refused probe → +14 −3; F27 login never retries → +16 −1. Baseline 17/17.
- Frontend suite 2064 / 14 skipped (`CLAUDE.md` §3 updated, verifier OK). CI 34273754093 green 5/5.
- Live, rebuilt bundle `--dart-define=BASE_URL=http://127.0.0.1:3000`, fresh Chrome profiles, backend `docker pause`d mid-request: **A** register `c8lost` → spinner past 15 s → unpause → shell within 6 s (server log: probe 401, then the flushed register created id 202, retry 409, sign-in 201 — the race path). **B** backend paused throughout → after ~30 s `Brak połączenia. Spróbuj ponownie.`, button re-enabled, exactly one register sent. **C** `c8taken` with the wrong password → taken line + `Przejdź do logowania`.
- Deployed web-only; smoke in `deploy-web.log`.

## Notes for next session

- Worst case is now 45 s of spinner (register 15 s + probe 15 s + retry 15 s) before the one-liner; that is the accepted trade for never showing the paragraph.
- The friend runs Umbra in a Safari TAB: no push, and installing the PWA later = a new device (different storage) → gate → link/restore. Owner told; "fine for now, native app coming".
- Text pass awaits the owner's strikes on `.planning/text-pass/proposal.md`; single release when approved. Ship with a screenshot pass on every touched screen (gate, devices, settings, passcode, notes).

## Addendum — 0.2.29 (`eb54641`, web-only): the text pass shipped

Owner: "go" on all 68. Two adjustments made while shipping: `passcodeNote` EN keeps "erasing this app's data" (the one substance test in `passcode_lock_screen_test.dart`), and `devicesEnableLinkingWebWarningBody` + `recoveryKeyRequiredForLinking` were de-duplicated because the enable-linking dialog renders both (they had become the same sentence twice). `peerIdentityFingerprintServedNotice` keeps its `{name}` placeholder. Applied via CRLF-safe line rewrite of both ARBs, `flutter gen-l10n`, analyzer clean, suite 2064/14. Screenshot pass on a rebuilt bundle: gate (link + restore + reset hint), Settings, banner body, Privacy top/mid/bottom, delete-history dialog, Devices, enable-linking dialog, passcode setup. Not screenshotted (no cheap path on the local drive): reset-ceremony statuses, revoke/mismatch/revoked notices, peer fingerprint sheet, recovery-phrase reveal, anti-quantum note reveal.

### What shipped (old text = previous ARB; new below)

| # | key | new PL | new EN |
|---|---|---|---|
| **Auth / session** | | | |
| 1 | authStatusSavedSessionUnreadable | Nie udało się odczytać sesji. Uruchom aplikację ponownie. | Could not read the session. Restart the app. |
| **Settings → info rows** | | | |
| 2 | uninstallWarning | Nie odinstalowuj i nie czyść danych — historia zniknie. | Don't uninstall or clear data — history is lost. |
| 3 | e2eEncryptionDescription | Szyfrowanie Signal. Treść widzisz tylko Ty i odbiorca. | Signal encryption. Only you and the recipient see the content. |
| 4 | yourEncryptionKeysDescription | Klucze są tylko na tym urządzeniu. Bez kopii nie da się ich odzyskać. | Keys live only on this device. Without a backup they can't be recovered. |
| 5 | singleDeviceEncryptionDescription | Każde urządzenie ma własne klucze. | Each device has its own keys. |
| 6 | webKeyStorageDescription | W przeglądarce klucze chroni tylko blokada kodem. | In a browser only the passcode lock protects the keys. |
| 7 | whatIsEncryptedDescription | Tekst, zdjęcia, głos, linki — wszystko end-to-end. | Text, images, voice, links — all end-to-end. |
| 8 | serverStoresMetadataDescription | Serwer widzi kto, z kim i kiedy. Nigdy treść. | The server sees who, with whom and when. Never the content. |
| 9 | deleteAllLocalHistoryDescription | Usuwa wiadomości z tego urządzenia. Konto i klucze zostają. | Deletes messages from this device. Account and keys stay. |
| 10 | deleteAllLocalHistoryDialogBody | Wiadomości z tego urządzenia znikną na zawsze. | Messages on this device are gone for good. |
| 11 | deleteConversationConfirm | Usunie wszystkie wiadomości z tej rozmowy. | Deletes every message in this conversation. |
| **Devices** | | | |
| 12 | devicesExplainer | Nowe urządzenie dodasz tylko z urządzenia głównego. | Add new devices from the primary device only. |
| 13 | devicesAlreadyEnrolled | Łączenie włączono na innym urządzeniu. Dodawaj stamtąd. | Linking is enabled on another device. Add from there. |
| 14 | devicesRevokeExplainer | Zostanie wylogowane. Jego wiadomości zostają. | It will be signed out. Its messages stay. |
| 15 | deviceRevokedNotice | To urządzenie usunięto z konta. Zaloguj się i połącz je ponownie. | This device was removed. Sign in and link it again. |
| 16 | deviceRevokedRestoredNotice | Konto przywrócono na innym urządzeniu. Połącz to ponownie. | Account restored on another device. Link this one again. |
| 17 | deviceMismatchBody | Klucze tego urządzenia zostały unieważnione. Połącz je ponownie z drugiego urządzenia. | This device's keys were revoked. Link it again from your other device. |
| 18 | linkNoDak | Łączyć można tylko z urządzenia, które włączyło łączenie. | Only the device that enabled linking can link. |
| 19 | linkNewExplainer | Na urządzeniu głównym: Połącz urządzenie → zeskanuj lub wpisz ten kod. | On the primary: Link a device → scan or type this code. |
| 20 | linkPrimaryShowCodeExplainer | Zeskanuj ten kod nowym urządzeniem. | Scan this code with the new device. |
| 21 | devicesInstallFirst | Najpierw zainstaluj Umbra jako aplikację (menu → Dodaj do ekranu). | Install Umbra as an app first (menu → Add to Home Screen). |
| 22 | devicesInstallNudge | Zainstaluj Umbra jako aplikację — przeglądarka może usunąć klucze. | Install Umbra as an app — the browser may evict the keys. |
| 23 | devicesEnableLinkingWebWarningBody | Tylko urządzenie główne dodaje i usuwa urządzenia. | Only the primary device adds and removes devices. |
| 24 | devicesBackupMissing | Brak kopii kluczy. Utwórz frazę odzyskiwania. | No key backup. Create a recovery phrase. |
| 25 | recoveryKeyRequiredForLinking | Łączenie wymaga frazy odzyskiwania — utworzysz ją za chwilę. | Linking requires a recovery phrase — you'll create it next. |
| **Gate (new device)** | | | |
| 26 | linkGateBody | To urządzenie nie ma kluczy konta. Połącz je z urządzenia głównego. | This device has no account keys. Link it from the primary device. |
| 27 | linkGateStaleBody | Klucze tutaj są nieaktualne — połączenie je zastąpi. | Keys here are stale — linking replaces them. |
| 28 | linkGateScanBody | Zeskanuj kod z urządzenia głównego albo pokaż mu ten. | Scan the primary's code, or show it this one. |
| 29 | linkGateCheckingBody | Sprawdzam, czy konto ma klucze na innym urządzeniu… | Checking whether the account has keys elsewhere… |
| 30 | linkGateRestoreBody | Wpisz 12 słów. To urządzenie stanie się głównym. | Enter the 12 words. This device becomes primary. |
| 31 | linkGateRestoreNoBackup | Brak kopii kluczy. Połącz z urządzenia głównego albo zresetuj. | No key backup. Link from the primary or reset. |
| 32 | linkGateResetHint | Reset: nowe klucze po 72 h, inne urządzenia wylogowane, stara historia przepada. | Reset: new keys after 72 h, other devices signed out, old history lost. |
| 33 | linkGateResetPendingBody | Za {remaining} konto dostanie nowe klucze. Odzyskałeś urządzenie główne? Anuluj i połącz stamtąd. | New keys in {remaining}. Got the primary back? Cancel and link from there. |
| 34 | linkGateResetPhraseTooNew | Klucz odzyskiwania ma mniej niż 3 dni — obowiązuje pełne 72 h. | Recovery key is under 3 days old — full 72 h apply. |
| **Reset ceremony** | | | |
| 35 | recoveryPhrasePromptBody | 12 słów skraca oczekiwanie z 72 h do 1 h. | The 12 words cut the wait from 72 h to 1 h. |
| 36 | identityResetStarted | Reset rozpoczęty. Możesz go anulować do końca odliczania. | Reset started. Cancel any time before the countdown ends. |
| 37 | identityResetPhraseTooNew | Reset rozpoczęty. Klucz ma mniej niż 3 dni, więc czekasz pełne 72 h. | Reset started. Key is under 3 days old, so the full 72 h apply. |
| 38 | identityResetCooldown | Reset niedawno anulowano. Nowy za maks. 24 h. Ktoś obcy anuluje? Zmień hasło. | Reset cancelled recently. Next in up to 24 h. Someone else cancelling? Change password. |
| 39 | identityResetPhraseRejected | Te 12 słów nie pasuje do tego konta. | Those 12 words don't match this account. |
| 40 | identityResetPhraseLocked | Zbyt wiele prób. Spróbuj za godzinę. | Too many attempts. Try again in an hour. |
| 41 | identityResetNotEnrolled | Reset niepotrzebny — zaloguj się na nowym urządzeniu. | No reset needed — just sign in on the new device. |
| 42 | identityResetNoAnswer | Brak odpowiedzi. Nic nie rozpoczęto — spróbuj ponownie. | No answer. Nothing started — try again. |
| 43 | identityResetPendingBody | Za {remaining} konto dostanie nowe klucze. To nie Ty? Anuluj teraz. | New keys in {remaining}. Not you? Cancel now. |
| 44 | ownIdentityReplacedBody | Nowe logowanie zmieniło klucze konta. To nie Ty? Zmień hasło. | A new sign-in changed the account keys. Not you? Change your password. |
| **Recovery phrase** | | | |
| 45 | recoveryKeyBackupExplainer | Te 12 słów przywraca konto po utracie urządzenia. Kto je zna, ma Twoje konto. Pokazujemy je raz. | These 12 words restore the account after losing a device. Whoever has them owns it. Shown once. |
| 46 | recoveryKeyShownOnceWarning | Pokazujemy je tylko raz. Zapisz teraz. | Shown only once. Save them now. |
| 47 | recoveryKeySaveFailed | Nie zapisano klucza. Te słowa nie działają — spróbuj ponownie. | Key not saved. These words won't work — try again. |
| **Peer key verification** | | | |
| 48 | peerIdentityFingerprintDialogDescription | Porównaj z {name} innym kanałem. Muszą się zgadzać. | Compare with {name} over another channel. They must match. |
| 49 | peerIdentityFingerprintChangedNotice | Klucz {name} się zmienił. Porównaj NOWY odcisk. | {name}'s key changed. Compare the NEW fingerprint. |
| 50 | peerIdentityFingerprintServedNotice | Klucz {name} z serwera, niepotwierdzony wiadomością. Porównaj go innym kanałem. | {name}'s key came from the server, unconfirmed by any message. Compare it out of band. |
| 51 | peerIdentityFingerprintOfferChanged | Klucz {name} zmienił się w trakcie. Porównaj ponownie. | {name}'s key changed meanwhile. Compare again. |
| 52 | peerIdentityFingerprintUnchangedNotice | Klucz {name} bez zmian od Twojej akceptacji. | {name}'s key unchanged since you accepted it. |
| 53 | peerIdentityFingerprintOfferUnavailable | Nie udało się pobrać klucza {name}. Sprawdź połączenie. | Couldn't load {name}'s key. Check the connection. |
| 54 | peerIdentityChangedTimelineRow | Klucze {name} się zmieniły. Dotknij, aby sprawdzić. | {name}'s keys changed. Tap to verify. |
| 55 | peerIdentityChangedSystemLine | {name}: nowe urządzenie lub przeglądarka — klucze zaktualizowane. | {name}: new device or browser — keys updated. |
| **Passcode** | | | |
| 56 | passcodeNoRecovery | Zapomnianego kodu nie da się odzyskać. | A forgotten passcode cannot be recovered. |
| 57 | passcodeNote | Zapomnisz kodu — jedyne wyjście to usunięcie danych aplikacji. | Forget it and the only way out is erasing this app's data. |
| 58 | passcodeEraseWarning | Usunie dane aplikacji. Wiadomości tylko stąd znikną na zawsze. | Erases the app's data. Messages only here are gone for good. |
| 59 | passcodeEraseWarningEnrolled | Usunie dane aplikacji. Potem przywrócisz konto frazą, z innego urządzenia lub resetem. | Erases the app's data. Then restore with the phrase, another device, or a reset. |
| 60 | passcodeErasePartial | Nie wszystko usunięto. Spróbuj ponownie. | Not everything was erased. Try again. |
| 61 | passcodeScopeNoteDevice | Blokuje aplikację na tym urządzeniu. Nie trafia na serwer. | Locks the app on this device. Never sent to the server. |
| 62 | passcodeScopeNoteBrowser | Szyfruje klucze w tej przeglądarce. Nie trafia na serwer. | Encrypts this browser's keys. Never sent to the server. |
| 63 | passcodeTooWeakForKeys | Własny kod: min. 6 znaków, nie tylko cyfry. | Custom code: 6+ characters, not digits only. |
| **Notes (anti-quantum)** | | | |
| 64 | antiQuantumNoteRevealWarning | Odczytasz ją tylko raz. Potem zniknie dla wszystkich. | You can read it once. Then it's gone for everyone. |
| 65 | privacyAntiQuantumNoteLead | Samoniszczące notatki z własnym szyfrowaniem. | Self-destructing notes with their own encryption. |
| 66 | privacyAntiQuantumNotePointDevice | Szyfrowane na Twoim urządzeniu, serwer widzi tylko szyfrogram. | Encrypted on your device; the server sees only ciphertext. |
| 67 | privacyAntiQuantumNotePointKey | Klucz jest w linku po #, którego serwer nigdy nie widzi. | The key sits after # in the link, which the server never sees. |
| 68 | privacyAntiQuantumNotePointTimer | Nieotwarte znikają po 1–24 h. | Unopened ones vanish after 1–24 h. |


## Addendum — 0.2.30 (`2b66d56`, web-only): release 1 of the gap list

Owner's answers to the "is multi-device finished" list: 3 (iOS rename dialog) verified on his phone; 4 (assetlinks) waits for the APK; 5 "seed phrase > password"; 6 → Q2 **6 h** reset, Q3 **phrase alone resets the password**; 7 "go" on clause-5 proof + hide `none_for_device` + video receive. Q2+Q3 recorded in spec (lxxxi) as owner decisions, NOT built — I stated the combined effect once (any single stolen secret suffices) and asked for a one-word "confirmed".

- **(lxxxi) pre-link history → one pill.** `MessagingProvider.messages` omits sentinel rows (lazy cache, invalidated in `notifyListeners`, returns `_messages` itself when nothing is hidden); `hiddenPreLinkCount`; `ChatDetailScreen` renders `MessageDateSeparator.label(historyBeforeDeviceLinked)` at the oldest end and in the all-hidden empty state. Dead bubble branches removed, `messageSentBeforeDeviceLinked` → `historyBeforeDeviceLinked`. `loadedMessagesForTest` keeps the I8 "never destroyed" assertion honest.
- **(lxxxi) clause 2 — clause 5 failed live.** Repro: user 204, K1 → browser B mints K2 (audit row) → B enrols with phrase `weasel … palace` → empty browser C restores → banner. Cause: first hydration hits the empty install (`own == null` fall-through reports), second hydration only skipped. Fix: own-key branch retracts an alarm showing for the SAME instant. Test RED → GREEN, F31 killed; re-driven on browser D: silent. Negative arm live too: browser A (K1) showed the banner for the foreign K2.
- **Video self-sync receive** test in `messaging_provider_self_sync_test.dart` (full envelope → media fields applied + persisted); F30 killed.
- Suite 2071/14, analyzer clean over lib/test/test_e2e.
- Seen, not touched: `recovery_key_screen` body starts 8 px under the header pill (same padding formula as Devices; per spec, looks tight).

Drive accounts on the local stack: `c9prim#8244` (id 204, phrase above), `c8lost`, `c8taken`, `c8dead` (password `Passw0rd!x`).

## Addendum — 0.2.31 (`4ba17ab`, BOTH tiers): (lxxxii) "the seed is the account"

Owner: "confirm all" after the combined-effect warning (any single stolen secret now suffices). Recorded in `docs/design/multi-device.md` §12 (lxxxii) as an explicit owner decision.

- **Clause 1:** `RESET_DELAY_MS` 72 h → **6 h** (`RECOVERY_MIN_AGE_MS` follows by definition). Copy: `linkGateResetHint`, `linkGateResetPhraseTooNew`, `recoveryPhrasePromptBody`, `identityResetPhraseTooNew`; root `CLAUDE.md` §7 and `frontend/CLAUDE.md` §5 updated (the latter still claimed "no key backup").
- **Clause 2:** `POST /auth/recover { identifier, phrase, newPassword }` — `RecoverPasswordDto`, `AuthService.recoverPassword` (resolve → `IdentityResetService.verifyRecoveryPhrase` → `UsersService.setPassword` → wait for the next whole second → `issueSession`). `verifyRecoveryPhrase` is the shortcut's verifier + counter + lockout extracted (`verifyAgainstRow`), never spending, `usedAt`/age ignored, success clears the counter. **Found while building: a token signed in the same second as `passwordChangedAt` is rejected by `JwtStrategy` (`iat <= stamp` in whole seconds)** — the door waits ≤1 s for the next second instead of back-dating the stamp; pinned by a test.
- **Client:** `AuthFormMode {login, register, recover}` (`AuthForm.onSubmit(username, password, phrase)`), "Nie pamiętam hasła" link, recover form with `RecoveryPhrase.isValid/normalize`, `AuthProvider.recoverPassword` (+ `_adoptSession` shared with `_signIn`), `AuthStatusCode.phraseRejected` ("Nazwa lub fraza nie pasuje."), 423 → `tooManyAttempts`.
- **Proof:** mutants F32–F36 killed (1 substitution each). Backend 1116/62, frontend 2078/14, analyzer clean, prettier on touched files, lint ratchet floor 894 → 898 (six `expect(mock.method)` assertions in new tests — the suite's idiom). Live on the local stack (dev backend hot-reloaded): curl — wrong phrase counted, right phrase → tokens, old password 401 / new 201; UI on a rebuilt bundle — wrong phrase → one line, right phrase → shell → the gate (enrolled account) reading "6 h".
- **Deploy:** backend FIRST (route + constant), then web.

- **Deployed:** backend `1e73567c` (`/version` 0.2.31, `/auth/recover` live: unknown name → 401), then web 0.2.31 / 1e73567, smoke 5/5. First CI run red (e2e `registration_lock_test` asserted `> 70` hours; backend count 1116 vs 1117 after the counter-reset test) — fixed in `1e73567`, CI 34294263704 green 5/5.

## Addendum — 0.2.32 (`110c200`, both tiers): the door's timing oracle closed

Review note, weighed and accepted: refusing an unknown identifier before any verify made `/auth/recover` enumerate usernames by response time, and my "memory cost" reason was hollow (an attacker names a real account to burn Argon2 anyway). `AuthService.recoverPassword` now runs `argon2.verify(TIMING_SAFE_DUMMY_ARGON2, phrase)` on the unknown/ambiguous path — same parameters as the real verifier — and spends no counter. `argon2` mocked in `auth.service.spec.ts`; three tests pin it; F37 killed. Ratchet held at 898 (one `any` access rewritten as `toHaveBeenCalledWith`). Deployed backend `110c200d` then web; prod unknown-name response ~120 ms (was instant).

Not changed, on purpose: `RECOVERY_MIN_AGE_MS` follows `RESET_DELAY_MS` to 6 h — the ratified (lxxxii) text says so and the (xlii) argument is relational (floor ≥ the window the shortcut removes); the pre-decision draft's "unchanged" was superseded.

## Addendum — 0.2.33 (`469f050`, both tiers): enrolled-vs-not timing closed

`verifyRecoveryPhrase` returned `invalid_phrase` at once when no `recovery_keys` row existed, so a known username leaked whether it had enrolled. The no-row branch now verifies against `TIMING_SAFE_DUMMY_VERIFIER` (constant moved into `identity-reset.service.ts`, shared with the unknown-identifier path in `AuthService`). `jest.spyOn(argon2, 'verify')` throws on the native module ("Cannot redefine property"), so the test asserts elapsed time > 15 ms — the property under test IS the cost. F38 killed (1 substitution). Prod after deploy, one sample each (5 / 15 min budget): unknown name 103 ms (first sample 270 ms with TLS setup), `___#7868` (unenrolled) 109 ms, `bob208#9939` (enrolled, no phrase) 122 ms. The 0.2.32 note's "same as a real one" was asserted from the unknown arm only — corrected here with both arms measured. Trap: `sed -i 's/^version: 0.2.32$/…/'` silently no-ops on the CRLF pubspec; the bump landed in a follow-up commit BEFORE deploy.
