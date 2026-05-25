# Code Review — Campfire/Fireplace (2026-03-11)

## Executive Summary

Przeprowadzono profesjonalny przegląd całej aplikacji (backend NestJS + frontend Flutter). Kod jest **spójny i funkcjonalny**, ale występują:

- **Martwy kod** — funkcje i pola nigdy nieużywane
- **Duplikacja logiki** — powtarzające się walidacje (blocked + friends)
- **Brak spójności payloadu** — `replyToMessageId` nie jest wysyłane z backendu
- **Zbyt duże pliki** — `ChatProvider` (~1512 linii) i `chat-friend-request.service.ts` (~428 linii)
- **Placeholdery** — TODO w Firebase/VAPID

**Testy:** Backend 86/86 ✅ | Flutter analyze: uruchomiony

---

## 1. Martwy / nieużywany kod

### 1.1 `getOtherUserDisplayHandle` — nigdy nieużywane

| Lokalizacja | Opis |
|-------------|------|
| `frontend/lib/providers/conversation_helpers.dart` (linie 22–25) | Definicja funkcji |
| `frontend/lib/providers/chat_provider.dart` (linie 291–292) | Delegacja do helpera |

**Problem:** Chat header używa `getOtherUserUsername` (tylko username). `getOtherUserDisplayHandle` zwraca `username#tag` — nigdzie nie jest wywoływane.

**Rekomendacja:** Usunąć `getOtherUserDisplayHandle` z `conversation_helpers.dart` i `chat_provider.dart`, albo zacząć używać tam, gdzie potrzebny jest pełny handle (np. w nagłówku chatu).

---

### 1.2 `MessageModel.parseMessageType` — publiczne, nieużywane

| Lokalizacja | Opis |
|-------------|------|
| `frontend/lib/models/message_model.dart` (linia 154) | `static MessageType parseMessageType(String? type)` |

**Problem:** Metoda jest publiczna, ale nigdy nie jest wywoływana z zewnątrz. Wewnętrznie używane jest `_parseMessageType`.

**Rekomendacja:** Usunąć `parseMessageType` lub zmienić na prywatne, jeśli planowane jest użycie w testach.

---

### 1.3 `dart:io` w `chat_provider.dart`

| Lokalizacja | Opis |
|-------------|------|
| `frontend/lib/providers/chat_provider.dart` (linia 3) | `import 'dart:io';` |

**Problem:** Używane tylko w bloku `!kIsWeb` (linie 870–874) do usuwania plików głosowych. Na web `dart:io` może powodować problemy przy buildzie.

**Rekomendacja:** Użyć conditional import:

```dart
import 'io_stub.dart' if (dart.library.io) 'dart:io.dart' as io;
// lub
import 'dart:io' show File; // tylko gdy !kIsWeb
```

Alternatywnie: przenieść usuwanie pliku do platform-specific helpera.

---

## 2. Duplikacja logiki

### 2.1 Walidacja „blocked + friends” w backendzie

Ten sam wzorzec powtarza się w wielu handlerach:

```
isBlockedByEither → areFriends → error jeśli blocked lub nie friends
```

| Plik | Handler | Linie |
|------|---------|-------|
| `chat-message.service.ts` | `handleSendMessage` | 46–65 |
| `chat-message.service.ts` | `handleSendPing` | 237–252 |
| `chat-conversation.service.ts` | `handleStartConversation` | 52–64 |
| `messages.controller.ts` | image upload | 63–68 |
| `messages.controller.ts` | voice upload | 139–141 |

**Rekomendacja:** Wydzielić wspólny helper:

```typescript
// np. w friends.service.ts lub nowym chat-validation.service.ts
async validateCanMessage(senderId: number, recipientId: number): Promise<void> {
  if (await this.blockedService.isBlockedByEither(senderId, recipientId)) {
    throw new ForbiddenException('Cannot message this user');
  }
  if (!(await this.friendsService.areFriends(senderId, recipientId))) {
    throw new ForbiddenException('You can only message friends');
  }
}
```

---

### 2.2 Wielokrotne tworzenie `ApiService` w frontendzie

| Lokalizacja | Kontekst |
|-------------|----------|
| `auth_provider.dart` | `ApiService(baseUrl: AppConfig.baseUrl)` — singleton w providerze |
| `chat_provider.dart` | `PushService(ApiService(...))` — linia 30 |
| `chat_provider.dart` | `ApiService(...)` — linia 837 (voice upload) |
| `chat_provider.dart` | `ApiService(...)` — linia 968 (image upload) |

**Problem:** ChatProvider tworzy nową instancję ApiService przy każdym voice/image upload. Nie jest to krytyczne (ApiService jest stateless), ale można uprościć przez pole `late final ApiService _api`.

**Rekomendacja (niski priorytet):** Dodać `late final ApiService _api = ApiService(baseUrl: AppConfig.baseUrl)` w ChatProvider i używać go wszędzie.

---

## 3. Niespójności payloadu

### 3.1 Brak `replyToMessageId` w payloadzie backendu

| Komponent | Stan |
|-----------|------|
| Backend `MessageMapper.toPayload` | Zwraca `replyTo: { id, content, senderUsername, messageType }` — **nie** `replyToMessageId` |
| Frontend `MessageModel.fromJson` | Oczekuje `replyToMessageId` z JSON |
| Frontend `retryFailedMessage` (linia 958) | Używa `message.replyToMessageId` przy retry |

**Problem:** Dla wiadomości przychodzących z backendu (messageSent, newMessage, messageHistory) pole `replyToMessageId` jest zawsze `null`. Retry traci informację o reply-to.

**Rekomendacja:** Dodać `replyToMessageId` do `MessageMapper.toPayload`:

```typescript
// message.mapper.ts
if (message.replyTo) {
  payload.replyToMessageId = message.replyTo.id;
  // ... existing replyTo object
}
```

Alternatywnie w `MessageModel.fromJson`:

```dart
replyToMessageId: json['replyToMessageId'] as int? ?? 
    (json['replyTo'] != null ? (json['replyTo'] as Map)['id'] as int? : null),
```

---

## 4. Zbyt duże pliki

| Plik | Linie | Uwagi |
|------|-------|-------|
| `frontend/lib/providers/chat_provider.dart` | ~1512 | Stan, E2E, socket, voice, reconnection — wszystko w jednym |
| `backend/src/chat/services/chat-friend-request.service.ts` | ~428 | Już w CLAUDE.md |
| `backend/src/chat/services/chat-message.service.ts` | ~602 | Wiele handlerów |

**Rekomendacja dla ChatProvider:**

- Wydzielić `ChatEncryptionMixin` lub `ChatEncryptionProvider` (E2E)
- Wydzielić `ChatVoiceHelper` (voice recording + upload)
- Zachować w ChatProvider: stan, socket, podstawowe operacje

---

## 5. Funkcje / miejsca „nic nie robiące”

### 5.1 Zamierzone no-op

| Miejsce | Opis |
|---------|------|
| `push-notifications.service.ts` (linia 18) | Early return gdy brak `FIREBASE_SERVICE_ACCOUNT` — oczekiwane |
| `chat.gateway.ts` (linie 216, 248) | Early return gdy odbiorca offline — „silent no-op” |
| `secure_context_stub.dart` | `isWebSecureContext() => true` — stub dla platform nie-web |

### 5.2 Placeholdery do uzupełnienia

| Plik | Treść |
|------|-------|
| `firebase_options.dart` (linia 47) | `appId: 'TODO_REPLACE_WITH_IOS_APP_ID'` |
| `push_service.dart` (linia 17) | `// TODO: Replace with your real VAPID key` |

---

## 6. Spójność i jakość kodu

### 6.1 Co działa dobrze

- **AppConfig / AppConstants** — używane konsekwentnie
- **conversation_helpers** — czyste helpery, używane poprawnie
- **Mappery backendu** — spójna struktura `toPayload()`
- **Brak zależności cyklicznych** — importy w porządku
- **Testy backendu** — 86 testów przechodzi

### 6.2 Potencjalne problemy

- **Pliki `nul`** w git status — artefakty Windows (NUL device). Dodać do `.gitignore` lub usunąć.
- **Reply-to preview** — zgodnie z CLAUDE.md: „Reply-to preview leaks content to server (should show 'Encrypted message')” — tech debt.

---

## 7. Plan napraw (priorytety)

| Priorytet | Zadanie | Status |
|-----------|---------|--------|
| **Wysoki** | Dodać `replyToMessageId` do MessageMapper.toPayload | ✅ Zrobione |
| **Średni** | Usunąć `getOtherUserDisplayHandle` (lub zacząć używać) | ✅ Zrobione |
| **Średni** | Wydzielić `validateCanMessage` w backendzie | ✅ Zrobione |
| **Niski** | Usunąć/ukryć `MessageModel.parseMessageType` | ✅ Zrobione |
| **Niski** | Conditional import dla `dart:io` w chat_provider | ✅ Zrobione |
| **Niski** | Centralizacja ApiService w ChatProvider | ✅ Zrobione |
| **Info** | Refaktor ChatProvider (split) | Do zrobienia |
| **Info** | Zastąpić placeholdery Firebase/VAPID przed produkcją | Zależne od konfiguracji |

---

## 8. Wnioski

Kod jest **spójny i czytelny**. Główne obszary do poprawy:

1. **Usunięcie martwego kodu** — `getOtherUserDisplayHandle`, `parseMessageType`
2. **Naprawa retry reply** — `replyToMessageId` w payloadzie
3. **Redukcja duplikacji** — `validateCanMessage`
4. **Uproszczenie ChatProvider** — rozbicie na mniejsze moduły (długoterminowo)

Aplikacja nie jest „rozciągnięta” w sensie zbędnych abstrakcji — raczej kilka funkcji nie jest używanych, a duplikacja walidacji wynika z naturalnego rozwoju. Refaktor ChatProvider poprawi maintainability.
