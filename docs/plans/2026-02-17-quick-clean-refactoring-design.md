# Quick Clean Refactoring Design

**Date:** 2026-02-17
**Scope:** Frontend (Flutter) + Backend (NestJS)
**Risk:** Minimal — only removing confirmed dead code and unused exports

---

## Step 1: Delete Dead Screen Files (Frontend)

Remove 3 unused screen files (345 lines total):

| File | Lines | Why Dead |
|------|-------|----------|
| `screens/archive_placeholder_screen.dart` | 20 | Placeholder "Coming soon", replaced by Contacts tab |
| `screens/friend_requests_screen.dart` | 188 | Replaced by `_FriendRequestsTab` in `AddOrInvitationsScreen` |
| `screens/new_chat_screen.dart` | 137 | Replaced by `_AddByEmailTab` in `AddOrInvitationsScreen` |

**Verification:** All 3 files have zero imports across the entire codebase.

## Step 2: Remove Unused Method (Frontend)

- Remove `clearStatus()` from `auth_provider.dart` — defined but never called from any screen or widget.

## Step 3: Cleanup Debug Prints (Frontend)

- Convert any `print()` calls to `debugPrint()` (only shows in debug builds)
- Remove excessive debug logging from `chat_input_bar.dart` (26 calls, mostly voice recording debug)
- Remove excessive debug logging from `chat_provider.dart` (17 calls)
- Keep error-related `debugPrint()` calls (voice_message_bubble, settings_screen, ping_effect_overlay)

## Step 4: Remove Unused Exports (Backend)

| Item | File | Why Unused |
|------|------|------------|
| `DeleteConversationDto` | `chat/dto/chat.dto.ts` | Imported but never used; code uses `DeleteConversationOnlyDto` |
| `toPayloadArray()` | `chat/mappers/conversation.mapper.ts` | Defined but never called |
| `toPayloadArray()` | `chat/mappers/user.mapper.ts` | Defined but never called |
| `toPayloadArray()` | `chat/mappers/friend-request.mapper.ts` | Defined but never called |
| Unused import `DeleteConversationDto` | `chat/services/chat-conversation.service.ts` | References removed DTO |
| Unused import `UserMapper` | `chat/services/chat-conversation.service.ts` | Never used in file |

## Step 5: Verification

- `flutter analyze` — no broken imports
- `npm run build` — backend compiles clean
