# Recenzja: Nowe okno rozmowy (Chat Screen Redesign)

**Data:** 2026-02-04  
**Zakres:** Tylko **okno rozmowy** — ChatDetailScreen, lista wiadomości, pasek wejścia, kafelki akcji, bąbelki, overlay ping.  
**Odniesienia:** CLAUDE.md, `docs/futures/plans/2026-02-04-chat-screen-redesign.md`, `docs/futures/2026-02-04-chat-screen-architecture.md`

---

## 1. Kontekst z CLAUDE.md

Z CLAUDE.md wynika:

- **Navigacja:** Tap w konwersację → `ChatDetailScreen(conversationId)` (mobile: push, desktop: wbudowany w prawy panel).
- **Breakpoint:** 600px (desktop = embedded).
- **Obecny stan chatu:** sendMessage/getMessages przez Socket.IO, MessageModel: id, content, senderId, conversationId, createdAt (bez delivery, expiresAt, messageType).

Plan redesignu rozszerza to o: wskaźniki dostawy, znikające wiadomości, ping, kafelki akcji, emoji, mic/send, overlay ping. Poniżej ocena **samego okna rozmowy** (layout, komponenty, spójność z planem).

---

## 2. Co jest już zaimplementowane i spójne

### 2.1 ChatDetailScreen

- **AppBar:** Wstecz, tytuł (username), po prawej AvatarCircle (radius 18) + PopupMenuButton (Unfriend) — zgodne z planem i architekturą.
- **Body:** `Stack(body, PingEffectOverlay)` — overlay pokazywany gdy `chat.showPingEffect`; po zakończeniu animacji `chat.clearPingEffect()`. Zgodne z planem.
- **Tryb embedded:** Osobny nagłówek (avatar + nazwa) + `Expanded(Stack(body, overlay))` — sensowny podział mobile vs desktop.
- **Timer countdown:** `Timer.periodic(1s)` + `setState` w initState, anulowanie w dispose — lista odświeża się co sekundę, bąbelki z `expiresAt` pokazują aktualny countdown. Zgodne z planem Task 4.2.
- **firstOrNull:** Użycie `conversations.where(...).firstOrNull` przy braku konwersacji zwraca null i unika crashu — ok.

### 2.2 ChatInputBar

- **Struktura:** Column: ChatActionTiles → wiersz (attach, TextField, emoji, mic/send) → EmojiPicker (gdy _showEmojiPicker). Zgodne z hierarchią z architektury.
- **Kontrolki:** Załącznik (galeria), pole tekstowe (maxLines: null, TextInputAction.send), przełącznik emoji/klawiatura, mic gdy pusto / send gdy jest tekst. Zgodne z planem Task 3.2.
- **Styl:** SafeArea(top: false), obramowanie, kolory z RpgTheme (inputBg, tabBorder, primaryColor). Spójne z resztą aplikacji.

### 2.3 ChatActionTiles

- **Sześć kafelków:** Timer, Ping, Camera, Draw, GIF, More — zgodne z planem.
- **Guard:** W `_sendPing` i `_openCamera` na początku jest sprawdzenie `chat.activeConversationId == null` i SnackBar „Open a conversation first”. Zgodne z uwagą 8 z sekcji „IMPORTANT IMPLEMENTATION NOTES”.
- **Wysokość 60, ListView horizontal, style z RpgTheme** — zgodne z architekturą.

### 2.4 ChatMessageBubble

- **Delivery icon:** Dla `isMine`: sending → Icons.access_time, sent → Icons.check, delivered → Icons.done_all (niebieski). Zgodne z planem Task 3.1.
- **Timer:** `_getTimerText()` zwraca "Xh" / "Xm" / "Xs" / "Expired". Wyświetlane obok czasu z ikoną timer_outlined.
- **Typy wiadomości:** text (Text), ping (ikona + "PING!"), image/drawing (Image.network z loading/error). Zgodne z planem i architekturą.
- **Styl:** MaxWidth 75%, zaokrąglenia asymetryczne, obramowanie 3px z lewej, kolory RpgTheme.

### 2.5 PingEffectOverlay

- **Animacja:** Scale 0.5→2, opacity 1→0, 800 ms, Curves.easeOut/easeIn. Zgodne z planem.
- **Dźwięk:** just_audio, assets/sounds/ping.mp3. Zgodne.
- **Bezpieczne zakończenie:** `_controller.forward().then((_) { if (mounted) widget.onComplete(); })` — uwaga 12 z IMPLEMENTATION NOTES jest uwzględniona.

---

## 3. Luki i rozbieżności (tylko okno rozmowy)

### 3.1 Brak przekazywania expiresIn przy wysyłce (ChatInputBar)

**Plan (Task 3.2):** W `_send()` użyć timera znikających wiadomości:

```dart
final expiresIn = chat.conversationDisappearingTimer;
chat.sendMessage(text, expiresIn: expiresIn);
```

**Kod:** `context.read<ChatProvider>().sendMessage(text);` — bez `expiresIn`.

**Efekt:** Nawet po ustawieniu timera w dialogu Timer, nowe wiadomości nie dostaną `expiresIn` i nie będą znikać po czasie. To dotyczy **zachowania okna chatu**.

**Rekomendacja:** W `ChatInputBar._send()` dodać odczyt timera i przekazać do sendMessage:

```dart
final chat = context.read<ChatProvider>();
final expiresIn = chat.conversationDisappearingTimer;
chat.sendMessage(text, expiresIn: expiresIn);
```

(Przy założeniu, że ChatProvider ma getter `conversationDisappearingTimer` i `sendMessage(String content, {int? expiresIn})` — zgodnie z planem.)

---

### 3.2 Obrazki w bąbelku bez ograniczenia szerokości

**Architektura:** „200px width” dla obrazków w wiadomościach.

**Kod:** `Image.network(message.mediaUrl!, fit: BoxFit.cover)` bez `width`/constraints.

**Efekt:** Duże zdjęcia mogą rozciągać bąbelek na całą szerokość (max 75% ekranu), co może wyglądać nieoptymalnie.

**Rekomendacja:** Dodać np. `width: 200` (lub constraints z maxWidth 200) do Image.network, ewentualnie z zachowaniem aspect ratio (np. BoxFit.contain w ograniczonym boxie).

---

### 3.3 EmojiPicker — minimalna konfiguracja

**Plan (Task 3.2):** Długa konfiguracja `Config(columns: 7, emojiSizeMax: 32, bgColor, indicatorColor, ...)` z kolorami RpgTheme.

**Kod:** `config: const Config()` — domyślna konfiguracja.

**Efekt:** Działa, ale wygląd emoji pickera może nie być w pełni zgrany z dark/light theme aplikacji.

**Rekomendacja:** Opcjonalnie w kolejnej iteracji dodać kolory z RpgTheme (np. bgColor, indicatorColor) zgodnie z planem; nie blokuje to działania okna chatu.

---

### 3.4 Plan vs kod — tempId przy optymistic message

**IMPORTANT IMPLEMENTATION NOTES (punkt 1):** Zastąpić dopasowanie po `content` przez **tempId**: klient wysyła `tempId`, backend zwraca go w `messageSent`, zamiana optymistic message po `tempId`.

**Plan Task 2.2 Step 7:** Nadal opisuje zamianę po `m.id < 0 && m.content == message.content`. Treść kroku nie została zaktualizowana do tempId.

**Kod (jeśli implementacja jest po starej wersji planu):** Może nadal używać dopasowania po content — wtedy przy dwóch takich samych tekstach pod rząd możliwa jest zamiana „niewłaściwej” wiadomości w oknie.

**Rekomendacja:**  
- W **planie** zaktualizować Task 2.2 Step 7 (oraz powiązane kroki backendu) tak, aby opisywały tempId i zamianę po tempId.  
- W **kodzie** (ChatProvider + backend payload messageSent) wdrożyć tempId zgodnie z IMPLEMENTATION NOTES. To bezpośrednio wpływa na poprawność listy wiadomości w oknie chatu.

---

### 3.5 Ścieżki w commitach w planie

W Task 1.1 Step 8 i Task 1.2 Step 6 w planie wciąż występuje:

`git add backend/src/messages/entities/message.entity.ts`

W projekcie encja jest w `backend/src/messages/message.entity.ts` (bez `entities/`). Uwaga 14 z IMPLEMENTATION NOTES to już poprawia w opisie, ale same komendy git w krokach nadal mają złą ścieżkę.

**Rekomendacja:** W tych krokach zamienić na `backend/src/messages/message.entity.ts`, żeby wykonujący plan nie dodawał nieistniejącego pliku do commita.

---

## 4. Spójność z architekturą (okno rozmowy)

| Element architektury | Stan w kodzie |
|----------------------|----------------|
| AppBar: [←] Username [Avatar] ⋮ | Zaimplementowane |
| Lista wiadomości (scroll) | ListView.builder + MessageDateSeparator |
| Bąbelek: czas + delivery + timer | Zaimplementowane |
| Action Tiles nad paskiem wejścia | ChatActionTiles nad wierszem input |
| Input: [📎] [Pole] [😊] [🎤/📤] | Zaimplementowane |
| Emoji picker 250px pod inputem | SizedBox(height: 250) + EmojiPicker |
| Stack + PingEffectOverlay | Zaimplementowane, z mounted check |
| Odświeżanie countdown co 1 s | Timer.periodic w ChatDetailScreen |

Układ i zachowanie **okna rozmowy** są zgodne z dokumentem architektury; brakuje głównie **expiresIn w _send()** oraz ewentualnie **tempId** i dopracowania obrazków/emoji.

---

## 5. Podsumowanie recenzji (tylko okno chatu)

- **Układ i komponenty** (AppBar, lista, input, kafelki, bąbelki, overlay) są zaimplementowane i zgodne z planem/architekturą.  
- **Krytyczne dla zachowania okna:**  
  - Dodać przekazywanie **expiresIn** w `ChatInputBar._send()`.  
  - Wdrożyć **tempId** dla optymistic message (plan + backend + ChatProvider) i zaktualizować opis w planie.  
- **Drobne:** Ograniczenie szerokości obrazka w bąbelku (np. 200px), opcjonalnie konfiguracja EmojiPicker z RpgTheme, poprawka ścieżek w komendach git w planie.

Po tych korektach **nowe okno rozmowy** jest spójne z CLAUDE.md, planem i architekturą oraz nadaje się do dalszego rozwoju (backend expiration, image upload, itd.) bez zmian w samym layoutcie okna.
