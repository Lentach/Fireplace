# Plan: Link Preview

## Context

Wiadomości tekstowe zawierające URL-e powinny automatycznie pokazywać podgląd strony (tytuł + obraz + opis) — tak jak w Messenger/iMessage. Backend asynchronicznie pobiera OG metadata po wysłaniu wiadomości i emituje `linkPreviewReady` do obu uczestników czatu. Frontend wyświetla kartę poniżej tekstu; URL w tekście jest klikalny (`url_launcher`).

Decyzje projektowe:
- Backend fetchuje (nie frontend — bezpieczeństwo, iOS-safe)
- Async fire-and-forget po `handleSendMessage` (nie blokuje send)
- 3 nowe kolumny w `messages` (nie osobna tabela)
- SSRF ochrona: blokada prywatnych IP + timeout 5s
- Node 20 global `fetch` — zero nowych npm packages
- `url_launcher ^6.3.1` w Flutter (już lub nowy dep)

---

## Krytyczne pliki

**Backend:**
- `backend/src/messages/message.entity.ts` — 3 nowe kolumny
- `backend/src/messages/messages.service.ts` — `updateLinkPreview()`
- `backend/src/messages/message.mapper.ts` — 3 nowe pola w payload
- `backend/src/chat/services/link-preview.service.ts` — **NOWY PLIK**
- `backend/src/chat/services/chat-message.service.ts` — async trigger po send
- `backend/src/chat/chat.module.ts` — rejestracja `LinkPreviewService`

**Frontend:**
- `frontend/pubspec.yaml` — dodać `url_launcher`
- `frontend/lib/models/message_model.dart` — 3 nowe pola + `copyWith`
- `frontend/lib/services/socket_service.dart` — `onLinkPreviewReady` listener
- `frontend/lib/providers/chat_provider.dart` — `_handleLinkPreviewReady()`
- `frontend/lib/widgets/chat_message_bubble.dart` — `_buildTextWithLinks()` + `_buildLinkPreviewCard()`

---

## Kroki implementacji

### 1. Backend — Entity

`message.entity.ts` — dodać 3 kolumny po `reactions`:
```typescript
@Column({ type: 'text', nullable: true, default: null })
linkPreviewUrl: string | null;

@Column({ type: 'text', nullable: true, default: null })
linkPreviewTitle: string | null;

@Column({ type: 'text', nullable: true, default: null })
linkPreviewImageUrl: string | null;
```
TypeORM `synchronize: true` → auto-apply po restarcie Dockera.

---

### 2. Backend — LinkPreviewService (NOWY PLIK)

`backend/src/chat/services/link-preview.service.ts`:

```typescript
import { Injectable, Logger } from '@nestjs/common';

const PRIVATE_IP_RE =
  /^(localhost|127\.|10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|::1|fc00:|fd)/i;

function extractFirstUrl(text: string): string | null {
  const match = text.match(/https?:\/\/[^\s<>"{}|\\^`\[\]]+/i);
  return match ? match[0] : null;
}

function isPrivateOrLocal(url: string): boolean {
  try {
    const { hostname } = new URL(url);
    return PRIVATE_IP_RE.test(hostname);
  } catch {
    return true;
  }
}

function parseOgMeta(html: string): {
  title: string | null;
  imageUrl: string | null;
} {
  const title =
    html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']/i)?.[1] ??
    html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']/i)?.[1] ??
    html.match(/<title[^>]*>([^<]+)<\/title>/i)?.[1] ??
    null;

  const imageUrl =
    html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i)?.[1] ??
    html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i)?.[1] ??
    null;

  return {
    title: title ? title.trim().substring(0, 200) : null,
    imageUrl: imageUrl ? imageUrl.trim() : null,
  };
}

@Injectable()
export class LinkPreviewService {
  private readonly logger = new Logger(LinkPreviewService.name);

  async fetchPreview(
    text: string,
  ): Promise<{ url: string; title: string | null; imageUrl: string | null } | null> {
    const url = extractFirstUrl(text);
    if (!url) return null;
    if (isPrivateOrLocal(url)) return null;

    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 5000);

      const response = await fetch(url, {
        signal: controller.signal,
        headers: { 'User-Agent': 'Mozilla/5.0 (compatible; ChatBot/1.0)' },
      });
      clearTimeout(timeout);

      if (!response.ok) return null;

      const contentType = response.headers.get('content-type') ?? '';
      if (!contentType.includes('text/html')) return null;

      // Read max 100KB to avoid large downloads
      const reader = response.body?.getReader();
      if (!reader) return null;
      let html = '';
      let totalBytes = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        totalBytes += value.byteLength;
        html += new TextDecoder().decode(value);
        if (totalBytes > 100_000) break;
      }
      reader.cancel();

      const { title, imageUrl } = parseOgMeta(html);
      if (!title && !imageUrl) return null;

      return { url, title, imageUrl };
    } catch (err) {
      this.logger.debug(`Link preview fetch failed for ${url}: ${err.message}`);
      return null;
    }
  }
}
```

---

### 3. Backend — MessagesService

`messages.service.ts` — dodać metodę `updateLinkPreview()`:
```typescript
async updateLinkPreview(
  messageId: number,
  url: string,
  title: string | null,
  imageUrl: string | null,
): Promise<Message | null> {
  const message = await this.msgRepo.findOne({ where: { id: messageId } });
  if (!message) return null;
  message.linkPreviewUrl = url;
  message.linkPreviewTitle = title;
  message.linkPreviewImageUrl = imageUrl;
  return this.msgRepo.save(message);
}
```

---

### 4. Backend — MessageMapper

`message.mapper.ts` — dodać w `toPayload()` po `reactions`:
```typescript
linkPreviewUrl: message.linkPreviewUrl ?? null,
linkPreviewTitle: message.linkPreviewTitle ?? null,
linkPreviewImageUrl: message.linkPreviewImageUrl ?? null,
```

---

### 5. Backend — ChatMessageService

`chat-message.service.ts`:

**Wstrzyknąć** `LinkPreviewService` w konstruktorze:
```typescript
constructor(
  private readonly messagesService: MessagesService,
  private readonly conversationsService: ConversationsService,
  private readonly friendsService: FriendsService,
  private readonly usersService: UsersService,
  private readonly linkPreviewService: LinkPreviewService,  // dodać
) {}
```

**W `handleSendMessage`** — po `client.emit('messageSent', messagePayload)` dodać async fire-and-forget:
```typescript
// Async link preview — fire and forget, does not block send
if (message.messageType === MessageType.TEXT && data.content) {
  this.linkPreviewService.fetchPreview(data.content).then(async (preview) => {
    if (!preview) return;
    const updated = await this.messagesService.updateLinkPreview(
      message.id,
      preview.url,
      preview.title,
      preview.imageUrl,
    );
    if (!updated) return;
    const previewPayload = {
      messageId: message.id,
      conversationId: conversation.id,
      linkPreviewUrl: preview.url,
      linkPreviewTitle: preview.title,
      linkPreviewImageUrl: preview.imageUrl,
    };
    client.emit('linkPreviewReady', previewPayload);
    if (recipientSocketId) {
      server.to(recipientSocketId).emit('linkPreviewReady', previewPayload);
    }
  }).catch(() => {/* swallow */});
}
```

---

### 6. Backend — ChatModule

`backend/src/chat/chat.module.ts` — zaimportować i zarejestrować `LinkPreviewService`:
```typescript
import { LinkPreviewService } from './services/link-preview.service';
// ...
providers: [
  ChatGateway,
  ChatMessageService,
  ChatConversationService,
  ChatFriendRequestService,
  LinkPreviewService,  // dodać
],
```

---

### 7. Frontend — pubspec.yaml

Dodać do `dependencies` (jeśli nie ma):
```yaml
url_launcher: ^6.3.1
```
Potem `flutter pub get`.

---

### 8. Frontend — MessageModel

`message_model.dart` — dodać 3 pola:
```dart
final String? linkPreviewUrl;
final String? linkPreviewTitle;
final String? linkPreviewImageUrl;
```

W `fromJson()`:
```dart
linkPreviewUrl: json['linkPreviewUrl'] as String?,
linkPreviewTitle: json['linkPreviewTitle'] as String?,
linkPreviewImageUrl: json['linkPreviewImageUrl'] as String?,
```

W `copyWith()`:
```dart
String? linkPreviewUrl,
String? linkPreviewTitle,
String? linkPreviewImageUrl,
// ...
linkPreviewUrl: linkPreviewUrl ?? this.linkPreviewUrl,
linkPreviewTitle: linkPreviewTitle ?? this.linkPreviewTitle,
linkPreviewImageUrl: linkPreviewImageUrl ?? this.linkPreviewImageUrl,
```

> Uwaga: `copyWith` ma wbudowany problem z nullable fields (nie da się wyzerować przez `null`). Nie ma potrzeby rozwiązywać tego teraz — preview są tylko addytywne.

---

### 9. Frontend — SocketService

`socket_service.dart` — w `connect()` dodać opcjonalny callback i jego rejestrację:

**Parametr:**
```dart
void Function(dynamic)? onLinkPreviewReady,
```

**Rejestracja** (obok innych listenerów):
```dart
if (onLinkPreviewReady != null) {
  _socket!.on('linkPreviewReady', onLinkPreviewReady);
}
```

---

### 10. Frontend — ChatProvider

`chat_provider.dart`:

**Handler:**
```dart
void _handleLinkPreviewReady(dynamic data) {
  final m = data as Map<String, dynamic>;
  final messageId = m['messageId'] as int;
  final index = _messages.indexWhere((msg) => msg.id == messageId);
  if (index == -1) return;
  _messages[index] = _messages[index].copyWith(
    linkPreviewUrl: m['linkPreviewUrl'] as String?,
    linkPreviewTitle: m['linkPreviewTitle'] as String?,
    linkPreviewImageUrl: m['linkPreviewImageUrl'] as String?,
  );
  notifyListeners();
}
```

**Wire w `connect()`:**
```dart
onLinkPreviewReady: _handleLinkPreviewReady,
```

---

### 11. Frontend — ChatMessageBubble

`chat_message_bubble.dart`:

**a) Klikalny URL w tekście** — zamiast zwykłego `Text()` dla `MessageType.text`:
```dart
// Zastąpić:
// Text(message.content, style: RpgTheme.bodyFont(...))

// Nowym:
_buildTextWithLinks(context, message.content, textColor),
```

Metoda:
```dart
Widget _buildTextWithLinks(BuildContext context, String text, Color textColor) {
  final urlRegex = RegExp(r'https?://[^\s]+', caseSensitive: false);
  final spans = <InlineSpan>[];
  int last = 0;

  for (final match in urlRegex.allMatches(text)) {
    if (match.start > last) {
      spans.add(TextSpan(
        text: text.substring(last, match.start),
        style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
      ));
    }
    final url = match.group(0)!;
    spans.add(TextSpan(
      text: url,
      style: RpgTheme.bodyFont(
        fontSize: 14,
        color: Colors.blue.shade300,
      ).copyWith(decoration: TextDecoration.underline),
      recognizer: TapGestureRecognizer()
        ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    ));
    last = match.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(
      text: text.substring(last),
      style: RpgTheme.bodyFont(fontSize: 14, color: textColor),
    ));
  }

  if (spans.isEmpty) {
    return Text(text, style: RpgTheme.bodyFont(fontSize: 14, color: textColor));
  }
  return RichText(text: TextSpan(children: spans));
}
```

**b) Karta podglądu** — po treści wiadomości (przed retry buttonem):
```dart
if (message.linkPreviewUrl != null)
  _buildLinkPreviewCard(context, isDark, textColor),
```

Metoda:
```dart
Widget _buildLinkPreviewCard(BuildContext context, bool isDark, Color textColor) {
  final cardBg = isDark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.black.withValues(alpha: 0.04);

  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: GestureDetector(
      onTap: () => launchUrl(
        Uri.parse(message.linkPreviewUrl!),
        mode: LaunchMode.externalApplication,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.linkPreviewImageUrl != null)
              Image.network(
                message.linkPreviewImageUrl!,
                width: double.infinity,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.linkPreviewTitle != null)
                    Text(
                      message.linkPreviewTitle!,
                      style: RpgTheme.bodyFont(
                        fontSize: 13,
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  Text(
                    message.linkPreviewUrl!,
                    style: RpgTheme.bodyFont(
                      fontSize: 11,
                      color: isDark ? RpgTheme.timeColorDark : RpgTheme.textSecondaryLight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

**Import wymagany:**
```dart
import 'package:flutter/gestures.dart';  // TapGestureRecognizer
import 'package:url_launcher/url_launcher.dart';
```

---

## Kolejność implementacji

1. Backend entity (krok 1) → restart Dockera (auto-sync)
2. `LinkPreviewService` nowy plik (krok 2)
3. `MessagesService.updateLinkPreview()` (krok 3)
4. `MessageMapper` 3 nowe pola (krok 4)
5. `ChatMessageService` — inject + fire-and-forget (krok 5)
6. `ChatModule` — rejestracja service (krok 6)
7. Frontend `pubspec.yaml` + `flutter pub get` (krok 7)
8. Frontend `MessageModel` 3 nowe pola (krok 8)
9. Frontend `SocketService` listener (krok 9)
10. Frontend `ChatProvider` handler (krok 10)
11. Frontend `ChatMessageBubble` — links + card (krok 11)
12. Aktualizacja CLAUDE.md

---

## Weryfikacja

1. Wyślij wiadomość z URL (np. `https://github.com`) → po ~2-3s karta pojawia się pod tekstem u obu uczestników
2. Tap na URL w tekście → otwiera przeglądarkę
3. Tap na kartę podglądu → otwiera przeglądarkę
4. Wyślij wiadomość bez URL → brak karty, zero zmian w UI
5. Wyślij URL prywatnego IP (`http://192.168.1.1`) → brak podglądu (SSRF blocked, backend log: "fetch failed")
6. Zamknij i otwórz ponownie czat → podgląd wciąż widoczny (persystuje w DB + przychodzi w `messageHistory`)
7. `flutter analyze` — 0 nowych błędów
