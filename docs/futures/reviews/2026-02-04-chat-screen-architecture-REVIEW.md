# Chat Screen Architecture & Plan — Code Review

**Date:** 2026-02-04  
**Reviewed:** `docs/futures/2026-02-04-chat-screen-architecture.md` + `docs/futures/plans/2026-02-04-chat-screen-redesign.md`  
**Verdict:** Plan ma szansę na sukces po poprawkach poniżej. Architektura jest spójna; w planie są błędy ścieżek, API i kilka luk, które trzeba uzupełnić przed implementacją.

---

## 1. Podsumowanie

| Obszar | Ocena | Uwagi |
|--------|--------|--------|
| Architektura (diagramy, flow) | ✅ Dobra | Spójna z Telegram/Wire, delivery + ping + timer są jasno opisane |
| Spójność z obecnym kodem | ⚠️ Częściowa | Ścieżki plików i nazwy metod w backendzie nie zgadzają się z repo |
| Przebieg implementacji | ✅ Dobry | Fazy 1–7 są logiczne, TDD/commit per task |
| Ryzyko bugów | ⚠️ Średnie | Kilka błędów w kodzie (Dart private, optymistic message, backend API) |
| Czytelność kodu w planie | ✅ Dobra | Fragmenty są zrozumiałe, nazewnictwo spójne |

**Rekomendacja:** Wprowadzić poprawki z sekcji 2–3 przed rozpoczęciem implementacji (lub na bieżąco w trakcie Phase 1–2).

---

## 2. Błędy i rozbieżności (do poprawy)

### 2.1 Ścieżki plików — Backend

| W planie | W projekcie | Działanie |
|----------|-------------|-----------|
| `backend/src/messages/entities/message.entity.ts` | `backend/src/messages/message.entity.ts` | Używać `message.entity.ts` (bez folderu `entities/`) |
| `backend/src/users/entities/user.entity.ts` | `backend/src/users/user.entity.ts` | Nie używane w planie; gdyby — `user.entity.ts` |

**Działanie:** W całym planie zamienić odwołania do `messages/entities/message.entity.ts` na `messages/message.entity.ts`.

---

### 2.2 Backend — ConversationsService API

W planie (Task 1.2, handleSendPing):

```typescript
let conversation = await this.conversationsService.findBetweenUsers(user.id, recipientId);
if (!conversation) {
  conversation = await this.conversationsService.createConversation(user.id, recipientId);
}
```

W projekcie **nie ma** `findBetweenUsers` ani `createConversation`. Jest:

- `findByUsers(userId1, userId2): Promise<Conversation | null>`
- `findOrCreate(userOne: User, userTwo: User): Promise<Conversation>`

**Poprawka:** W `handleSendPing` zrobić tak jak w `handleSendMessage`: pobrać `sender` i `recipient` z `UsersService`, potem:

```typescript
const sender = await this.usersService.findById(user.id);
const recipient = await this.usersService.findById(recipientId);
if (!sender || !recipient) {
  client.emit('error', { message: 'User not found' });
  return;
}
const conversation = await this.conversationsService.findOrCreate(sender, recipient);
```

I usunąć wywołania `findBetweenUsers` / `createConversation`.

---

### 2.3 Message entity — JoinColumn i spójność

Obecna encja ma:

- `@JoinColumn({ name: 'sender_id' })` przy `sender`
- `@JoinColumn({ name: 'conversation_id' })` przy `conversation`

W planie nowa encja tego nie pokazuje. Przy rozszerzaniu encji **zachować** istniejące `ManyToOne` + `JoinColumn` i dodać tylko nowe kolumny (`deliveryStatus`, `expiresAt`, `messageType`, `mediaUrl`). Inaczej TypeORM wygeneruje inne nazwy kolumn i mogą się pojawić błędy migracji/odczytu.

---

### 2.4 Flutter — MessageModel._parseDeliveryStatus (private)

W Task 2.2 plan każe w `ChatProvider._handleMessageDelivered` wywołać:

```dart
deliveryStatus: MessageModel._parseDeliveryStatus(status),
```

W Dart `_parseDeliveryStatus` to metoda **prywatna w obrębie biblioteki** (plik). Z innego pliku (`chat_provider.dart`) nie można wywołać `MessageModel._parseDeliveryStatus`.

**Poprawka:** W `message_model.dart` dodać publiczną metodę statyczną, np.:

```dart
static MessageDeliveryStatus parseDeliveryStatus(String? status) {
  switch (status?.toUpperCase()) {
    case 'SENDING': return MessageDeliveryStatus.sending;
    case 'SENT': return MessageDeliveryStatus.sent;
    case 'DELIVERED': return MessageDeliveryStatus.delivered;
    default: return MessageDeliveryStatus.sent;
  }
}
```

W `ChatProvider` używać: `MessageModel.parseDeliveryStatus(status)` (bez podkreślnika). Wewnętrznie `fromJson` może dalej używać tej samej logiki (np. wywołując `parseDeliveryStatus`).

---

### 2.5 Optymistic message — identyfikacja po `content`

Plan (Task 2.2, Step 7): przy `messageSent` usuwać optymistic message po:

```dart
final tempIndex = _messages.indexWhere((m) => m.id < 0 && m.content == message.content);
```

Jeśli użytkownik wyśle dwa takie same teksty pod rząd, można usunąć „niewłaściwą” wiadomość lub zaktualizować zły element.

**Rekomendacja:** Dodać po stronie klienta **tymczasowe id** (np. `tempId = DateTime.now().millisecondsSinceEpoch`) i przekazać je w `sendMessage`; backend w `messageSent` zwraca ten sam `tempId` (w payloadzie). Zamiana: szukać po `m.id == tempId` (jeśli trzymamy tempId w modelu) lub po `tempId` w payloadzie i dopasować do jednej wiadomości. To wymaga rozszerzenia DTO i payloadu `messageSent` w planie i w architekturze.

---

### 2.6 SocketService — sygnatura connect i brak metod

Plan zakłada dodanie do `connect()` parametrów `onMessageDelivered` i `onPingReceived`. Obecna sygnatura używa **wyłącznie nazwanych** parametrów (np. `onMessageSent`, `onNewMessage`). Trzeba dodać dokładnie te dwa, bez zmiany pozostałych.

Brakuje też:

- Emisji `messageDelivered` po stronie klienta (odbiorca po otrzymaniu `newMessage` ma wywołać `emit('messageDelivered', { messageId })`). W planie jest to w `_handleIncomingMessage`, ale **SocketService** nie ma metody do emisji dowolnego eventu ani konkretnie `messageDelivered`.
- Metody do wysłania wiadomości z `expiresIn` (obecne `sendMessage(recipientId, content)` nie przyjmuje `expiresIn`).
- Metody do `sendPing(recipientId)`.

**Działanie:** W planie w Phase 2 (Task 2.2) doprecyzować:

- W `SocketService`: dodać `emitMessageDelivered(int messageId)`, `sendMessage(recipientId, content, {int? expiresIn})`, `sendPing(recipientId)`.
- W `connect()` dodać dwa nowe nazwane callbacki: `onMessageDelivered`, `onPingReceived`, i zarejestrować listenery `messageDelivered` oraz `newPing`.

---

### 2.7 ChatProvider — token do uploadu obrazków

W Task 5.2 plan mówi: „get token from AuthProvider or stored”. W `ChatProvider` przy `connect(token, userId)` jest już `_tokenForReconnect = token`, ale nie ma zwykłego `_token` do użycia w API.

**Działanie:** W `connect()` zapisać token także do pola używane do wywołań HTTP, np. `_token = token`, i w `sendImageMessage` użyć tego pola (oraz `ApiService(AppConfig.baseUrl)` lub wstrzykniętego serwisu). Nie polegać wyłącznie na `_tokenForReconnect`, żeby nie mieszać semantyki „reconnect” z „wywołania API”.

---

### 2.8 ApiService — instancja i baseUrl

Plan: `ApiService().uploadImageMessage(...)`. W projekcie `ApiService` ma konstruktor `ApiService({required this.baseUrl})`. Wywołanie `ApiService()` bez argumentu się nie skompiluje.

**Działanie:** Albo przekazać `ApiService` do `ChatProvider` (np. z main/providerów), albo w `sendImageMessage` użyć np. `ApiService(baseUrl: AppConfig.baseUrl)` i zapisanego w providerze tokena. To spójne z punktem 2.7.

---

### 2.9 Cloudinary — brak uploadImage

W planie `MessagesController` wywołuje `this.cloudinaryService.uploadImage(file.buffer)`. W projekcie jest tylko `uploadAvatar(userId, buffer, mimeType)` i `deleteAvatar(publicId)`.

**Działanie:** W planie (Phase 5) dodać krok: rozszerzenie `CloudinaryService` o metodę `uploadImage(buffer: Buffer, mimeType: string, options?: { folder?: string })` zwracającą np. `{ url: string, publicId: string }`, oraz użycie jej w kontrolerze. Ewentualnie osobny folder dla obrazków w wiadomościach (np. `messages/`).

---

### 2.10 MessagesService.createImageMessage — zależności

Plan każe w `MessagesService` dodać `createImageMessage(senderId, recipientId, mediaUrl, expiresIn)`, z wewnętrznym sprawdzeniem znajomości i konwersacji. Obecny `MessagesService` ma tylko `msgRepo`; nie ma `FriendsService`, `ConversationsService`, `UsersService`.

**Działanie:** W `MessagesModule` zaimportować `FriendsModule`, `ConversationsModule`, `UsersModule` i wstrzyknąć te serwisy do `MessagesService`. Unikać cykli: `ConversationsModule` już importuje `Message` (TypeORM), więc nie powinien importować `MessagesModule`; `MessagesModule` importujący `ConversationsModule` i `FriendsModule` jest OK.

Alternatywa: trzymać logikę „znajdź/utwórz konwersację + sprawdź znajomych” w `ChatMessageService` i wywołać tam `MessagesService.create(..., messageType, mediaUrl, expiresAt)` (po rozszerzeniu `create`), żeby nie duplikować logiki i nie rozbudowywać zależności `MessagesService` — wtedy zależności zostają w jednym miejscu.

---

### 2.11 Backend — Multer i file.buffer

Plan: `@UploadedFile() file: Express.Multer.File` i `file.buffer`. Domyślna konfiguracja Multer w Nest (np. `FileInterceptor('file')`) często daje `file` w pamięci tylko po użyciu `memoryStorage()`. Trzeba jawnie skonfigurować `MulterModule.register({ storage: memoryStorage() })` (albo equivalent), żeby mieć `file.buffer`. W przeciwnym razie `file.buffer` może być undefined.

**Działanie:** W planie (Task 5.1) dodać krok konfiguracji Multer z `memoryStorage()` (np. w `MessagesModule` lub `AppModule`) i w kontrolerze sprawdzać `file?.buffer` przed przekazaniem do Cloudinary.

---

### 2.12 Action Tiles — brak kontekstu konwersacji

W Task 3.3 przy `_sendPing(context)` i `_openCamera(context)` plan robi:

```dart
final conv = chat.conversations.firstWhere((c) => c.id == chat.activeConversationId);
```

Gdy `activeConversationId == null` (np. użytkownik wszedł w „Add” zamiast w konkretny chat), `firstWhere` rzuci.

**Działanie:** Na początku akcji (Ping, Camera, Draw itd.) dodać guard:

```dart
if (chat.activeConversationId == null) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Open a conversation first')),
  );
  return;
}
```

Dopiero potem `conversations.firstWhere(...)` i `getOtherUserId(conv)`.

---

### 2.13 Drawing canvas — moment przechwytywania obrazu

W Task 5.2 `_sendDrawing` wywołuje `_canvasKey.currentContext!.findRenderObject() as RenderRepaintBoundary` i od razu `toImage()`. W pierwszej klatce po otwarciu ekranu layout może być jeszcze nie gotowy.

**Działanie:** Przed `toImage()` użyć np. `WidgetsBinding.instance.addPostFrameCallback((_) { ... })` lub upewnić się, że wywołanie jest po zbudowaniu (np. w callbacku po naciśnięciu „Send”). W planie to doprecyzować w opisie kroku „Capture canvas as image”.

---

### 2.14 EmojiPicker — Config / CategoryIcons

Plan używa `Config(..., categoryIcons: const CategoryIcons(), ...)`. W nowszych wersjach `emoji_picker_flutter` API `Config` i `CategoryIcons` mogło się zmienić (np. inna nazwa lub wymagane inne parametry).

**Działanie:** Przy implementacji sprawdzić w pub.dev / changelog `emoji_picker_flutter` aktualną sygnaturę `Config` i ewentualnie dostosować fragment z planu (np. `EmojiPickerConfig` zamiast `Config`). To nie jest błąd w samym planie, tylko ryzyko przy aktualnych wersjach pakietu.

---

## 3. Drobne uwagi (jakość kodu i spójność)

- **Timer.periodic w ChatDetailScreen:** Odświeżanie co 1 s przez `setState(() {})` przebudowuje cały ekran. W sekcji „Performance Considerations” architektury jest słuszna uwaga: docelowo warto ograniczyć przebudowę tylko do bąbelków z aktywnym timerem. Na start obecne podejście jest akceptowalne.
- **PingEffectOverlay:** W `_controller.forward().then((_) { widget.onComplete(); })` warto dodać `if (mounted) widget.onComplete();`, żeby nie wywoływać callbacku po dispose.
- **Dokumentacja CLAUDE.md:** Ścieżka w planie to `docs/CLAUDE.md`; w drzewie projektu plik to `CLAUDE.md` w katalogu głównym. Upewnić się, że w Task 7.1 edytowany jest faktyczny plik (np. `CLAUDE.md` w root).
- **messageHistory / getMessages:** Backend w `handleGetMessages` mapuje wiadomości bez pól `deliveryStatus`, `expiresAt`, `messageType`, `mediaUrl`. Po dodaniu tych pól do encji trzeba rozszerzyć mapowanie w `handleGetMessages` (i ewentualnie w `messages.service.ts`), żeby starsze konwersacje wyświetlały się z domyślnymi wartościami (np. SENT, TEXT, null). W planie warto to wpisać w Task 1.1 / 2.1 jako „rozszerz payload messageHistory o nowe pola”.

---

## 4. Co jest dobre

- **Architektura:** Delivery (SENDING → SENT → DELIVERED), timer per konwersacja, ping jako osobny typ wiadomości, obrazki przez HTTP + Cloudinary — wszystko jest spójne i realistyczne.
- **Fazy:** Kolejność Backend → Model/Provider → UI → Cron → Image jest sensowna i ogranicza ryzyko merge’ów.
- **Bezpieczeństwo:** Walidacja MIME, tylko znajomi, cron tylko po stronie serwera — dobre założenia.
- **Testy i weryfikacja:** Manual test checklist i Task 6.1 dają jasny plan odbioru.
- **Troubleshooting i ograniczenia:** Sekcje w architekturze (timer 30s vs cron 1 min, brak read receipts, ping rate limit) są uczciwe i pomogą przy utrzymaniu.

---

## 5. Szansa na sukces

- **Tak**, pod warunkiem że przed (lub na początku) implementacji:
  - poprawi się ścieżki i API backendu (ConversationsService, Message entity, MessagesService/Cloudinary),
  - poprawi się dostęp do `parseDeliveryStatus` i tokena/ApiService w Flutter,
  - doda się brakujące metody w SocketService i obsługę optymistic message (najlepiej z tempId),
  - uzupełni się Cloudinary (uploadImage) i Multer (memoryStorage),
  - doda się guard przy action tiles przy braku aktywnej konwersacji.

Po tych poprawkach plan jest spójny z architekturą i z obecnym kodem; implementacja krok po kroku według planu ma realną szansę zakończyć się działającą funkcjonalnością bez większych refaktorów.

---

**Koniec review.**
