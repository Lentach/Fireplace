# Security & Reliability Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the Fireplace messenger for production by eliminating 7 concrete security and reliability gaps found in the post-development review.

**Architecture:** Backend-first changes (NestJS) that tighten authentication, rate-limiting, and input validation; followed by a frontend-backend joint change to add authenticated media fetch and message pagination; a JWT payload cleanup that removes stale profile data; and a health-check endpoint for container orchestration.

**Tech Stack:** NestJS 11 · TypeORM · Passport/JWT · Flutter 3.x · Socket.IO 4 · `http` package (Dart) · `@nestjs/throttler` · `just_audio`

---

## File Map

| File | Change |
|---|---|
| `backend/src/users/user.entity.ts` | Add `passwordChangedAt` column |
| `backend/src/users/users.service.ts` | Set `passwordChangedAt` in `resetPassword` |
| `backend/src/auth/strategies/jwt.strategy.ts` | Reject tokens issued at/before `passwordChangedAt` |
| `backend/src/auth/auth.service.ts` | Remove `profilePictureUrl` from JWT payload |
| `backend/src/users/users.controller.ts` | Add `GET /users/me` endpoint |
| `backend/src/chat/chat.gateway.ts` | Add `@UseGuards(WsThrottlerGuard)` to 7 unguarded events |
| `backend/src/media/media.controller.ts` | Add `@UseGuards(JwtAuthGuard)` to `serveMsgs` |
| `backend/src/media/magic-bytes.validator.ts` | **New** — validates avatar magic bytes |
| `backend/src/health/health.controller.ts` | **New** — `GET /health` with 503 on DB failure |
| `backend/src/health/health.module.ts` | **New** |
| `backend/src/app.module.ts` | Import `HealthModule` |
| `frontend/nginx.conf` | Forward `Authorization` header to `/media/` proxy |
| `frontend/lib/services/api_service.dart` | Add `fetchMediaBytes(url, token)` and `fetchMe(token)` |
| `frontend/lib/providers/auth_provider.dart` | `_loadSavedToken` + `login` + `uploadProfilePicture` use `fetchMe`; 401 vs network-error distinction |
| `frontend/lib/widgets/message/image_message_content.dart` | Authenticated fetch |
| `frontend/lib/widgets/message/gif_message_content.dart` | Authenticated fetch |
| `frontend/lib/widgets/message/file_message_content.dart` | Convert to `StatefulWidget`; authenticated fetch |
| `frontend/lib/widgets/audio/playback_controller.dart` | Authenticated fetch (web-encrypted + native paths only) |
| `frontend/lib/providers/messaging_provider.dart` | `getMessages()` wrapper, `loadOlderMessages()`, pagination state, decrypt for paginated messages |
| `frontend/lib/screens/chat_detail_screen.dart` | 3 `getMessages` call sites redirected to `MessagingProvider`; load-more in existing `_onScroll` |

---

## Task 1: JWT Invalidation After Password Change

**Why:** After `POST /users/reset-password` the old token stays valid until natural expiry. An attacker who stole a token retains access even after the victim changes their password.

**Note:** The `validate` method in this task still declares `profilePictureUrl` in the payload type. Task 5 removes `profilePictureUrl` from the JWT — when implementing Task 5 also remove it from this type declaration.

**Files:**
- Modify: `backend/src/users/user.entity.ts`
- Modify: `backend/src/users/users.service.ts`
- Modify: `backend/src/auth/strategies/jwt.strategy.ts`

- [ ] **Step 1: Add `passwordChangedAt` column to User entity**

In `backend/src/users/user.entity.ts`, add after `createdAt`:
```ts
@Column({ type: 'timestamp', nullable: true })
passwordChangedAt: Date | null;
```
`Column` is already imported.

- [ ] **Step 2: Stamp `passwordChangedAt` in `resetPassword`**

In `backend/src/users/users.service.ts`, find `resetPassword`. After `user.password = await bcrypt.hash(...)` and before `await this.usersRepo.save(user)`:
```ts
user.passwordChangedAt = new Date();
```

- [ ] **Step 3: Add `iat` check in JWT strategy**

In `backend/src/auth/strategies/jwt.strategy.ts`, update `validate`:
```ts
async validate(payload: {
  sub: number;
  username: string;
  tag: string;
  profilePictureUrl: string; // removed in Task 5
  iat: number; // seconds since epoch — standard JWT claim, always present
}) {
  const user = await this.usersService.findById(payload.sub);
  if (!user) throw new UnauthorizedException();

  // Reject tokens issued at or before the last password change.
  // Use <= so a token issued in the same second as the change is also rejected.
  if (user.passwordChangedAt) {
    const changedAtSeconds = Math.floor(user.passwordChangedAt.getTime() / 1000);
    if (payload.iat <= changedAtSeconds) {
      throw new UnauthorizedException('Token invalidated by password change');
    }
  }

  return {
    id: user.id,
    username: user.username,
    tag: user.tag,
    profilePictureUrl: user.profilePictureUrl,
  };
}
```

Note: `usersService.findById` is already called on every request in the existing strategy — this does not add a new DB call.

- [ ] **Step 4: Write unit tests**

Create `backend/src/auth/jwt.strategy.spec.ts`:
```ts
import { JwtStrategy } from './strategies/jwt.strategy';
import { UnauthorizedException } from '@nestjs/common';

describe('JwtStrategy.validate', () => {
  let strategy: JwtStrategy;
  const mockUsersService = { findById: jest.fn() };
  const mockConfigService = { get: jest.fn().mockReturnValue('test-secret') };

  beforeEach(() => {
    strategy = new JwtStrategy(mockUsersService as any, mockConfigService as any);
  });

  it('rejects when user not found', async () => {
    mockUsersService.findById.mockResolvedValue(null);
    await expect(strategy.validate({ sub: 1, username: 'a', tag: '1234', profilePictureUrl: '', iat: 1000 }))
      .rejects.toThrow(UnauthorizedException);
  });

  it('accepts token issued after passwordChangedAt', async () => {
    mockUsersService.findById.mockResolvedValue({
      id: 1, username: 'a', tag: '1234', profilePictureUrl: null,
      passwordChangedAt: new Date(900 * 1000), // changed at t=900s
    });
    const result = await strategy.validate({ sub: 1, username: 'a', tag: '1234', profilePictureUrl: '', iat: 1000 });
    expect(result.id).toBe(1);
  });

  it('rejects token issued before passwordChangedAt', async () => {
    mockUsersService.findById.mockResolvedValue({
      id: 1, username: 'a', tag: '1234', profilePictureUrl: null,
      passwordChangedAt: new Date(1000 * 1000),
    });
    await expect(strategy.validate({ sub: 1, username: 'a', tag: '1234', profilePictureUrl: '', iat: 900 }))
      .rejects.toThrow(UnauthorizedException);
  });

  it('rejects token issued in the same second as passwordChangedAt', async () => {
    mockUsersService.findById.mockResolvedValue({
      id: 1, username: 'a', tag: '1234', profilePictureUrl: null,
      passwordChangedAt: new Date(1000 * 1000),
    });
    await expect(strategy.validate({ sub: 1, username: 'a', tag: '1234', profilePictureUrl: '', iat: 1000 }))
      .rejects.toThrow(UnauthorizedException);
  });

  it('accepts when passwordChangedAt is null', async () => {
    mockUsersService.findById.mockResolvedValue({
      id: 1, username: 'a', tag: '1234', profilePictureUrl: null,
      passwordChangedAt: null,
    });
    const result = await strategy.validate({ sub: 1, username: 'a', tag: '1234', profilePictureUrl: '', iat: 1 });
    expect(result.id).toBe(1);
  });
});
```

- [ ] **Step 5: Run tests**
```bash
cd backend && npm test -- --testPathPattern=jwt.strategy
```
Expected: 5 tests pass.

- [ ] **Step 6: Commit**
```bash
git add backend/src/users/user.entity.ts backend/src/users/users.service.ts backend/src/auth/strategies/jwt.strategy.ts backend/src/auth/jwt.strategy.spec.ts
git commit -m "feat(auth): invalidate JWT on password change via passwordChangedAt timestamp"
```

---

## Task 2: WebSocket Rate Limits on Unguarded Events

**Why:** Only `sendMessage` has `@UseGuards(WsThrottlerGuard)`. Seven other WS events are unthrottled — an attacker can hammer the database via WebSocket without any limit.

**Pattern:** `sendMessage` uses only `@UseGuards(WsThrottlerGuard)` without a `@Throttle` decorator (relies on global default: 100 req/15min). Apply the same pattern to all 7 new events. `Throttle` is already imported in `chat.gateway.ts` — no import changes needed.

**Files:**
- Modify: `backend/src/chat/chat.gateway.ts`

- [ ] **Step 1: Add `@UseGuards(WsThrottlerGuard)` to 7 handlers**

In `backend/src/chat/chat.gateway.ts`, add `@UseGuards(WsThrottlerGuard)` immediately above each `@SubscribeMessage` decorator for these handlers (same position as on `sendMessage`, no `@Throttle`):

- `handleGetMessages` — `@SubscribeMessage('getMessages')`
- `handleGetConversations` — `@SubscribeMessage('getConversations')`
- `handleGetFriends` — `@SubscribeMessage('getFriends')`
- `handleGetFriendRequests` — `@SubscribeMessage('getFriendRequests')`
- `handleGetBlockedList` — `@SubscribeMessage('getBlockedList')`
- `handleSearchUsers` — `@SubscribeMessage('searchUsers')`
- `handleFetchPreKeyBundle` — `@SubscribeMessage('fetchPreKeyBundle')`

Example:
```ts
@UseGuards(WsThrottlerGuard)
@SubscribeMessage('getMessages')
async handleGetMessages(...) { ... }
```

- [ ] **Step 2: Run backend tests**
```bash
cd backend && npm test
```
Expected: all existing tests pass.

- [ ] **Step 3: Commit**
```bash
git add backend/src/chat/chat.gateway.ts
git commit -m "feat(security): add WsThrottlerGuard to 7 unguarded WebSocket events"
```

---

## Task 3: Magic Bytes Validation on Avatar Upload

**Why:** Avatar uploads are unencrypted JPEG/PNG. The Multer `fileFilter` checks the MIME type from the request header — which the client controls. A malicious client can send a `.exe` with `Content-Type: image/jpeg`. Magic bytes validation checks the actual file bytes.

**Scope:** Only `avatar` uploads are unencrypted and require this validation. `image`, `gif`, `voice`, and `file` are all AES-256-GCM encrypted on the client before upload — they arrive as opaque binary blobs and cannot be validated by magic bytes.

**Files:**
- Create: `backend/src/media/magic-bytes.validator.ts`
- Modify: `backend/src/media/media.controller.ts`
- Modify: `backend/src/users/users.controller.ts`

- [ ] **Step 1: Create `magic-bytes.validator.ts`**

Create `backend/src/media/magic-bytes.validator.ts`:
```ts
import { BadRequestException } from '@nestjs/common';

function startsWith(buf: Buffer, bytes: number[]): boolean {
  return bytes.every((b, i) => buf[i] === b);
}

/**
 * Validates that a buffer is JPEG or PNG by checking magic bytes.
 * Call ONLY for avatar uploads — all other media types are encrypted blobs.
 */
export function validateAvatarMagicBytes(buffer: Buffer): void {
  const isJpeg = startsWith(buffer, [0xff, 0xd8, 0xff]);
  const isPng  = startsWith(buffer, [0x89, 0x50, 0x4e, 0x47]);
  if (!isJpeg && !isPng) {
    throw new BadRequestException('Avatar must be a JPEG or PNG image.');
  }
}
```

- [ ] **Step 2: Call validator in `MediaController.upload` avatar branch**

In `backend/src/media/media.controller.ts`, add the import and call:
```ts
import { validateAvatarMagicBytes } from './magic-bytes.validator';

// Inside upload(), in the avatar branch:
if (dto.mediaType === 'avatar') {
  validateAvatarMagicBytes(file.buffer); // ← add before storage call
  const result = await this.storage.uploadAvatar(userId, file.buffer, file.mimetype);
  return { mediaUrl: result.secureUrl };
}
```

- [ ] **Step 3: Call validator in `UsersController.uploadProfilePicture`**

In `backend/src/users/users.controller.ts`, add the import and call inside `uploadProfilePicture`, after the null check:
```ts
import { validateAvatarMagicBytes } from '../media/magic-bytes.validator';

// Inside uploadProfilePicture(), after: if (!file) throw ...
validateAvatarMagicBytes(file.buffer); // ← add here
```

- [ ] **Step 4: Write unit tests**

Create `backend/src/media/magic-bytes.validator.spec.ts`:
```ts
import { validateAvatarMagicBytes } from './magic-bytes.validator';
import { BadRequestException } from '@nestjs/common';

describe('validateAvatarMagicBytes', () => {
  it('accepts JPEG', () => {
    expect(() => validateAvatarMagicBytes(Buffer.from([0xff, 0xd8, 0xff, 0xe0]))).not.toThrow();
  });
  it('accepts PNG', () => {
    expect(() => validateAvatarMagicBytes(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))).not.toThrow();
  });
  it('rejects EXE (MZ header)', () => {
    expect(() => validateAvatarMagicBytes(Buffer.from([0x4d, 0x5a, 0x00, 0x00]))).toThrow(BadRequestException);
  });
  it('rejects empty buffer', () => {
    expect(() => validateAvatarMagicBytes(Buffer.alloc(0))).toThrow(BadRequestException);
  });
  it('rejects GIF', () => {
    expect(() => validateAvatarMagicBytes(Buffer.from([0x47, 0x49, 0x46, 0x38]))).toThrow(BadRequestException);
  });
});
```

- [ ] **Step 5: Run tests**
```bash
cd backend && npm test -- --testPathPattern=magic-bytes
```
Expected: 5 tests pass.

- [ ] **Step 6: Commit**
```bash
git add backend/src/media/magic-bytes.validator.ts backend/src/media/magic-bytes.validator.spec.ts backend/src/media/media.controller.ts backend/src/users/users.controller.ts
git commit -m "feat(security): validate magic bytes on avatar upload to prevent filetype spoofing"
```

---

## Task 4: Auth Guard on /media/msgs + Authenticated Frontend Fetch

**Why:** `GET /media/msgs/:filename` is currently public — anyone with a filename can download the blob. Blobs are AES-256-GCM encrypted but the metadata leak (who exchanged files) is a privacy violation.

**Note on audio web-legacy path:** `PlaybackController` has a path that calls `_audioPlayer.setUrl(mediaUrl)` directly without `http.get`. This path only fires when `mediaKey == null` (legacy Cloudinary URLs). Since `fetchMediaBytes` already skips the `Authorization` header for non-`/media/msgs/` URLs, this path needs no modification — Cloudinary URLs are not affected by the guard.

**Files:**
- Modify: `backend/src/media/media.controller.ts`
- Modify: `frontend/nginx.conf`
- Modify: `frontend/lib/services/api_service.dart`
- Modify: `frontend/lib/widgets/message/image_message_content.dart`
- Modify: `frontend/lib/widgets/message/gif_message_content.dart`
- Modify: `frontend/lib/widgets/message/file_message_content.dart` (convert to StatefulWidget)
- Modify: `frontend/lib/widgets/audio/playback_controller.dart`

**Sub-step 4a: Backend**

- [ ] **Step 1: Add JWT guard to `serveMsgs`**

In `backend/src/media/media.controller.ts`, add `@UseGuards(JwtAuthGuard)` to `serveMsgs` only (not `serveAvatars` — avatars stay public):
```ts
@Get('msgs/:filename')
@UseGuards(JwtAuthGuard)          // ← add
@Throttle({ default: { limit: 60, ttl: 60000 } })
async serveMsgs(@Param('filename') filename: string, @Res() res: Response) {
  // body unchanged
}
```

- [ ] **Step 2: Forward Authorization header in Nginx**

In `frontend/nginx.conf`, find the `/media/` location block. Add `proxy_set_header Authorization $http_authorization;`:
```nginx
location /media/ {
    proxy_pass http://backend:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header Authorization $http_authorization;   # ← add
}
```
Without this, Nginx strips the JWT before it reaches NestJS in production.

- [ ] **Step 3: Run backend tests**
```bash
cd backend && npm test
```
Expected: all tests pass.

**Sub-step 4b: Frontend**

- [ ] **Step 4: Add `fetchMediaBytes` to `ApiService`**

In `frontend/lib/services/api_service.dart`, add at end of class:
```dart
/// Fetches a media blob. Sends Authorization header only for own-server /media/msgs/ URLs.
/// Legacy Cloudinary URLs are fetched without auth.
Future<Uint8List> fetchMediaBytes(String url, String token) async {
  final headers = url.contains('/media/msgs/')
      ? {'Authorization': 'Bearer $token'}
      : <String, String>{};
  final response = await http.get(Uri.parse(url), headers: headers);
  if (response.statusCode != 200) {
    throw Exception('Media fetch failed: ${response.statusCode}');
  }
  return response.bodyBytes;
}
```

- [ ] **Step 5: Update `image_message_content.dart`**

In `frontend/lib/widgets/message/image_message_content.dart`, in `_loadDecryptedBytes()`:
1. Capture token **before** any `await` (CLAUDE.md rule: capture providers before first await):
   ```dart
   final token = context.read<AuthProvider>().token ?? '';
   ```
2. Replace `final response = await http.get(Uri.parse(url));` with:
   ```dart
   final raw = await ApiService(baseUrl: AppConfig.baseUrl).fetchMediaBytes(url, token);
   ```
3. Replace `Uint8List.fromList(response.bodyBytes)` with `raw`.

Note: `ApiService` is instantiated as `ApiService(baseUrl: AppConfig.baseUrl)` — it is NOT in the Provider tree. Do NOT use `context.read<ApiService>()`.

- [ ] **Step 6: Update `gif_message_content.dart`**

Same pattern as Step 5. In the `_load()` method, capture token before await, replace `http.get` with `fetchMediaBytes`.

- [ ] **Step 7: Convert `file_message_content.dart` to `StatefulWidget` and update fetch**

`FileMessageContent` is currently a `StatelessWidget`. The `_downloadDocument` method is async and called after a dialog (two Navigator pops) — using `context.read` after an await in a stateless context violates `use_build_context_synchronously`. Convert to `StatefulWidget` so that the token is stored in the state before any async gap:

```dart
class FileMessageContent extends StatefulWidget {
  // same constructor
  @override
  State<FileMessageContent> createState() => _FileMessageContentState();
}

class _FileMessageContentState extends State<FileMessageContent> {
  // In the method that triggers download:
  Future<void> _downloadDocument(BuildContext context) async {
    final token = context.read<AuthProvider>().token ?? ''; // capture BEFORE any await
    final url = widget.message.mediaUrl;
    if (url == null) return;
    final raw = await ApiService(baseUrl: AppConfig.baseUrl).fetchMediaBytes(url, token);
    // rest of existing logic using raw bytes
  }
}
```

- [ ] **Step 8: Update `playback_controller.dart` — web-encrypted and native paths**

`PlaybackController` has 3 audio paths. Only 2 need updating (the ones that call `http.get`):

**Path 1 — Web encrypted** (fires when `mediaKey != null && mediaIv != null`):
```dart
// Capture token BEFORE await (state context is always valid here)
final token = context.read<AuthProvider>().token ?? '';
final raw = await ApiService(baseUrl: AppConfig.baseUrl).fetchMediaBytes(mediaUrl, token);
// Replace response.bodyBytes with raw below
```

**Path 2 — Web unencrypted legacy** (calls `_audioPlayer.setUrl(mediaUrl)` — NO CHANGE NEEDED):
This path only fires when `mediaKey == null`, meaning it is always a legacy Cloudinary URL.
`fetchMediaBytes` already skips auth for non-`/media/msgs/` URLs, so `_audioPlayer.setUrl` continues
to work as-is. Do NOT modify this path.

**Path 3 — Native `_downloadAndCache`**:
```dart
final token = context.read<AuthProvider>().token ?? ''; // BEFORE await
final raw = await ApiService(baseUrl: AppConfig.baseUrl).fetchMediaBytes(url, token);
// Replace response.bodyBytes with raw
```

- [ ] **Step 9: Run Flutter tests**
```bash
cd frontend && flutter test
```
Expected: all tests pass.

- [ ] **Step 10: Commit**
```bash
git add backend/src/media/media.controller.ts frontend/nginx.conf frontend/lib/services/api_service.dart frontend/lib/widgets/message/image_message_content.dart frontend/lib/widgets/message/gif_message_content.dart frontend/lib/widgets/message/file_message_content.dart frontend/lib/widgets/audio/playback_controller.dart
git commit -m "feat(security): JWT auth on /media/msgs; authenticated media fetch in Flutter; Nginx header forward"
```

---

## Task 5: Remove profilePictureUrl from JWT + Add GET /users/me

**Why:** JWT carries `profilePictureUrl`. After avatar update the app reads the stale URL from the saved token on restart. JWTs should carry minimal claims.

**Note:** Also update the `validate` payload type in `jwt.strategy.ts` (added in Task 1) to remove `profilePictureUrl`.

**Files:**
- Modify: `backend/src/auth/auth.service.ts`
- Modify: `backend/src/auth/strategies/jwt.strategy.ts`
- Modify: `backend/src/users/users.controller.ts`
- Modify: `frontend/lib/services/api_service.dart`
- Modify: `frontend/lib/providers/auth_provider.dart`

**Sub-step 5a: Backend**

- [ ] **Step 1: Remove `profilePictureUrl` from JWT payload**

In `backend/src/auth/auth.service.ts`, in `login()`:
```ts
const payload = {
  sub: user.id,
  username: user.username,
  tag: user.tag,
  // profilePictureUrl removed — call GET /users/me for fresh profile data
};
```

- [ ] **Step 2: Clean up `validate` payload type in JWT strategy**

In `backend/src/auth/strategies/jwt.strategy.ts`, remove `profilePictureUrl` from the payload type annotation (added in Task 1):
```ts
async validate(payload: {
  sub: number;
  username: string;
  tag: string;
  iat: number;
  // profilePictureUrl removed
}) { ... }
```
The return value still includes `profilePictureUrl` (read from DB via `findById`) — only the payload type changes.

- [ ] **Step 3: Add `GET /users/me` endpoint**

In `backend/src/users/users.controller.ts`:
1. Add `Get` and `UnauthorizedException` to the `@nestjs/common` imports (`Request` is already imported)
2. Add the endpoint:
```ts
@Get('me')
@UseGuards(JwtAuthGuard)
async getMe(@Request() req) {
  const user = await this.usersService.findById(req.user.id);
  if (!user) throw new UnauthorizedException();
  return {
    id: user.id,
    username: user.username,
    tag: user.tag,
    profilePictureUrl: user.profilePictureUrl ?? null,
  };
}
```

**Sub-step 5b: Frontend**

- [ ] **Step 4: Add `fetchMe` to `ApiService`**

In `frontend/lib/services/api_service.dart`:
```dart
Future<Map<String, dynamic>> fetchMe(String token) async {
  final response = await http.get(
    Uri.parse('$baseUrl/users/me'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (response.statusCode != 200) {
    throw Exception('fetchMe failed: ${response.statusCode}');
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}
```

- [ ] **Step 5: Update `_loadSavedToken` in `AuthProvider`**

In `frontend/lib/providers/auth_provider.dart`, find `_loadSavedToken`. After restoring `_token`, replace the JWT-payload-based `_currentUser` construction with `fetchMe`. Distinguish network error from auth failure by checking the HTTP status code before throwing in `fetchMe`:

First, update `fetchMe` in `ApiService` to embed the status code into the exception in a recognisable way — change the throw to include a distinct prefix:
```dart
// In ApiService.fetchMe, change the throw to:
throw Exception('HTTP_${response.statusCode}: fetchMe failed');
```

Then in `_loadSavedToken`:
```dart
// After: _token = savedToken;
try {
  final userData = await _api.fetchMe(_token!);
  _currentUser = UserModel.fromJson(userData);
} on Exception catch (e) {
  if (e.toString().startsWith('Exception: HTTP_401')) {
    // Token genuinely expired → clear session
    _token = null;
    await prefs.remove('jwt_token');
    notifyListeners();
    return;
  }
  // Network unreachable or server error: keep _token set, _currentUser stays null.
  // Socket connect will fail and the reconnect manager will handle retry.
}
```

- [ ] **Step 6: Update `login` in `AuthProvider`**

In `AuthProvider.login()`, after receiving the access token and saving it, replace the JWT-payload-based `_currentUser` with:
```dart
final userData = await _api.fetchMe(_token!);
_currentUser = UserModel.fromJson(userData);
```
Remove any old code that parses `profilePictureUrl` from the JWT payload.

- [ ] **Step 7: Update `uploadProfilePicture` in `AuthProvider`**

After a successful avatar upload, replace the manual `_currentUser.copyWith(profilePictureUrl: ...)` with:
```dart
final userData = await _api.fetchMe(_token!);
_currentUser = UserModel.fromJson(userData);
```

- [ ] **Step 8: Run both test suites**
```bash
cd backend && npm test
cd frontend && flutter test
```
Expected: all tests pass.

- [ ] **Step 9: Commit**
```bash
git add backend/src/auth/auth.service.ts backend/src/auth/strategies/jwt.strategy.ts backend/src/users/users.controller.ts frontend/lib/services/api_service.dart frontend/lib/providers/auth_provider.dart
git commit -m "feat(auth): remove profilePictureUrl from JWT; add GET /users/me for fresh profile data"
```

---

## Task 6: Health Check Endpoint

**Why:** Docker has no way to know if NestJS is ready (DB connected, modules initialized). Without a health check, Docker restarts a crashed container blindly and load balancers route to unhealthy instances.

**Critical detail:** The endpoint must return HTTP 503 (not 200) when the DB is unreachable, otherwise Docker's `wget`-based healthcheck receives a 200 and never triggers a container restart.

**Files:**
- Create: `backend/src/health/health.controller.ts`
- Create: `backend/src/health/health.module.ts`
- Modify: `backend/src/app.module.ts`
- Modify: `docker-compose.yml`

- [ ] **Step 1: Create `health.controller.ts`**

Create `backend/src/health/health.controller.ts`:
```ts
import { Controller, Get, Res, HttpStatus } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import type { Response } from 'express';

@Controller('health')
export class HealthController {
  constructor(@InjectDataSource() private dataSource: DataSource) {}

  @Get()
  async check(@Res() res: Response) {
    try {
      await this.dataSource.query('SELECT 1');
      return res.status(HttpStatus.OK).json({ status: 'ok', db: 'ok' });
    } catch {
      // Return 503 so Docker healthcheck marks the container as unhealthy
      return res.status(HttpStatus.SERVICE_UNAVAILABLE).json({ status: 'degraded', db: 'error' });
    }
  }
}
```

- [ ] **Step 2: Create `health.module.ts`**

Create `backend/src/health/health.module.ts`:
```ts
import { Module } from '@nestjs/common';
import { HealthController } from './health.controller';

@Module({ controllers: [HealthController] })
export class HealthModule {}
```

- [ ] **Step 3: Import in `AppModule`**

In `backend/src/app.module.ts`:
```ts
import { HealthModule } from './health/health.module';
// add HealthModule to imports array
```

- [ ] **Step 4: Add healthcheck to `docker-compose.yml`**

Under the `backend` service:
```yaml
healthcheck:
  test: ["CMD", "wget", "-qO-", "http://localhost:3000/health"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 10s
```

- [ ] **Step 5: Verify**
```bash
curl -v http://localhost:3000/health
# Expected: HTTP 200, body: {"status":"ok","db":"ok"}
```

- [ ] **Step 6: Commit**
```bash
git add backend/src/health/ backend/src/app.module.ts docker-compose.yml
git commit -m "feat(infra): add GET /health with DB liveness check; 503 on degraded; docker healthcheck"
```

---

## Task 7: Frontend Message Pagination (Load Older Messages)

**Why:** `getMessages` fetches the 50 most recent messages and replaces the list entirely. All older messages are permanently inaccessible from the client in long conversations.

**Architecture decisions:**
- `MessagingProvider.getMessages(int conversationId)` is introduced as the single entry point for message loading. `ChatDetailScreen` has **3 call sites** that currently call `socketService.getMessages()` directly — all 3 must be redirected.
- Use `_messageLoadGeneration` (integer counter, not a boolean) to detect stale responses from concurrent loads.
- Paginated messages are also E2E encrypted — must call `_decryptMessageHistory` for them too.
- `ChatDetailScreen` already has `_scrollController`, `_onScroll`, and scroll listener wired up — only add load-more logic to the existing `_onScroll`, do NOT create a duplicate controller.

**Files:**
- Modify: `frontend/lib/providers/messaging_provider.dart`
- Modify: `frontend/lib/screens/chat_detail_screen.dart`

- [ ] **Step 1: Add pagination state fields to `MessagingProvider`**

In `frontend/lib/providers/messaging_provider.dart`, add near the existing `_messages` field:
```dart
static const int _pageSize = 50;
bool _isLoadingMore = false;
bool _hasMore = false;
int _paginationConversationId = -1;
int _paginationOffset = 0;   // tracks messages fetched from server, NOT _messages.length
bool _isPaginationLoad = false;
```

Note: Do NOT add a new generation counter — the existing `_decryptHistoryGeneration` field already handles this.

Add public getters:
```dart
bool get isLoadingMore => _isLoadingMore;
bool get hasMoreMessages => _hasMore;
```

**Additional local state fields for `_ChatDetailScreenState`** (NOT in `MessagingProvider`):
```dart
bool _isLoadingMoreLocal = false;   // drives spinner immediately on scroll-to-top
double? _prePaginationScrollOffset; // user's scroll position before pagination was triggered
double? _prePaginationScrollExtent; // maxScrollExtent before pagination was triggered
```
These are documented here for completeness — they are added in Steps 7 and 8. Do NOT declare them again in Step 8.

- [ ] **Step 2: Add `MessagingProvider.getMessages(int conversationId)`**

Add this new public method (wraps `_emit` with pagination state reset):
```dart
/// Single entry point for initial message load. Resets all pagination state.
/// ChatDetailScreen must call this — do NOT call socketService.getMessages() directly.
void getMessages(int conversationId) {
  _paginationConversationId = conversationId;
  _paginationOffset = 0;
  _isPaginationLoad = false;
  _hasMore = false;
  _emit('getMessages', {
    'conversationId': conversationId,
    'limit': _pageSize,
    'offset': 0,
  });
}
```

- [ ] **Step 3: Add `loadOlderMessages(int conversationId)`**

```dart
/// Loads the next page of older messages. No-op if already loading or no more pages.
/// Intentionally does NOT call notifyListeners() — the loading indicator is managed
/// by local widget state (_isLoadingMoreLocal) in ChatDetailScreen. The provider
/// notifies exactly once: when onMessageHistory completes with the pagination result.
/// Calling notifyListeners() here would trigger _onNewMessages in ChatDetailScreen
/// before any messages have arrived, causing premature UI state updates.
void loadOlderMessages(int conversationId) {
  if (_isLoadingMore || !_hasMore) return;
  _isLoadingMore = true;
  _isPaginationLoad = true;
  _emit('getMessages', {
    'conversationId': conversationId,
    'limit': _pageSize,
    'offset': _paginationOffset,  // offset tracked separately from _messages.length
  });
}
```

- [ ] **Step 4: Update `onMessageHistory` for pagination**

In `onMessageHistory`, after extracting `responseConversationId` and `list`, and **after** the existing early-return guard (`if (responseConversationId != effectiveActive) return;`) — never before it — insert the pagination branch:

```dart
final newMessages = list
    .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
    .toList();

if (_isPaginationLoad) {
  // Guard: reject responses for wrong conversation (stale concurrent load)
  if (responseConversationId != null && responseConversationId != _paginationConversationId) {
    _isLoadingMore = false;
    _isPaginationLoad = false;
    // Call notifyListeners() so ChatDetailScreen sees isLoadingMore=false and clears its spinner.
    notifyListeners();
    return;
  }

  // **Server sort order:** The backend's `findByConversation` must return messages in
  // `createdAt ASC` order (oldest-first) for the prepend to produce correct display order.
  // Verify by checking `messages.service.ts` → `findByConversation` ORDER BY clause.
  // The initial `getMessages` response also uses the same endpoint — if chat displays
  // correctly today (oldest at top), the sort is already ASC and no reversal is needed.
  // If sort is DESC (newest-first), add `.reversed.toList()` before the prepend below.

  // Prepend older messages (backend returns them oldest-first / createdAt ASC)
  _messages = [...newMessages, ..._messages];
  // Advance offset by how many messages actually arrived from the server
  _paginationOffset += newMessages.length;
  _hasMore = newMessages.length == _pageSize;
  _isLoadingMore = false;
  _isPaginationLoad = false;
  notifyListeners();
  // Paginated messages are also E2E encrypted — decrypt them using the same pattern
  // as the initial load. Set _decryptingHistory so that incoming live messages are
  // queued rather than processed in parallel while the ratchet is advancing.
  _decryptHistoryGeneration++;
  final myGeneration = _decryptHistoryGeneration;
  final int cacheId = _paginationConversationId; // capture now — _paginationConversationId may change before .whenComplete fires
  _decryptingHistory = true;
  _decryptMessageHistory(myGeneration).whenComplete(() {
    if (_decryptHistoryGeneration == myGeneration) {
      _decryptingHistory = false;
    }
    _updateCache(cacheId); // use captured ID — safe if user navigated to another chat
  });
  return;
}

// Initial load path (existing behavior):
// Use _paginationConversationId as stale-response guard (set by getMessages())
if (responseConversationId != null && responseConversationId != _paginationConversationId) {
  return;
}

// Replace _messages with newMessages
_messages = newMessages; // replaces existing `_messages = list.map(...).toList();`
_hasMore = newMessages.length == _pageSize;
_paginationOffset = newMessages.length; // tracks how many messages fetched from server
// ... rest of existing onMessageHistory logic unchanged (remove expired, notifyListeners, cache, decrypt)
```

**Important:** Verify that `_decryptMessageHistory` takes a single `int` generation argument and operates on `_messages` directly. Use the same signature as the existing call in the initial-load path. Do not pass `_messages` as a parameter.

**Safety of decrypting the full list:** After prepending, `_messages` contains `newMessages` at indices `0..newMessages.length-1` followed by the already-decrypted tail. `_decryptMessageHistory` uses cache-first decryption (CLAUDE.md, E2E Encryption section): it checks the persisted `EncryptionProvider` cache before attempting Signal decrypt. Tail messages that were already decrypted will be served from cache without advancing the ratchet — this is safe. However, if you discover that `_decryptMessageHistory` advances the ratchet even when a cache hit exists, the safe fallback is: record `final newCount = newMessages.length` BEFORE the prepend statement, then after prepending scope the decrypt loop to only `_messages.sublist(0, newCount)`. Check the implementation first — if it already guards on non-null content or has a cache hit short-circuit, no change is needed.

- [ ] **Step 5: Update `clearMessages` to reset pagination state**

Find `clearMessages()`, add:
```dart
_hasMore = false;
_paginationOffset = 0;
_isLoadingMore = false;
_isPaginationLoad = false;
_paginationConversationId = -1;
```

- [ ] **Step 6: Redirect 3 `getMessages` call sites in `ChatDetailScreen`**

In `frontend/lib/screens/chat_detail_screen.dart`, search for ALL calls to `socketService.getMessages(widget.conversationId` (or similar). There are **3 call sites**:
1. In `initState` / `addPostFrameCallback`
2. In `didUpdateWidget`
3. In `RefreshIndicator.onRefresh` (pull-to-refresh)

Replace each with:
```dart
context.read<MessagingProvider>().getMessages(widget.conversationId);
```
Use `context.read<>()` — capture before any `await`. For the async `RefreshIndicator.onRefresh` callback, capture the provider reference before the async gap:
```dart
onRefresh: () async {
  final messaging = context.read<MessagingProvider>(); // before await
  messaging.getMessages(widget.conversationId);
},
```

- [ ] **Step 7: Add load-more logic to existing `_onScroll`**

`ChatDetailScreen` already has `_scrollController`, `_onScroll` (managing `_showScrollToBottomButton` and `_wasNearBottom`), and the listener attached. Do NOT create a new controller or add a new listener. Find the existing `_onScroll` method and **append** the load-more block at the **end** of the existing method body — preserve all existing logic intact:

```dart
void _onScroll() {
  // *** KEEP all existing body here unchanged (e.g. _showScrollToBottomButton, _wasNearBottom) ***

  // Load older messages when scrolled near the top
  if (_scrollController.position.pixels <=
      _scrollController.position.minScrollExtent + 300) {
    final messaging = context.read<MessagingProvider>();
    if (!messaging.isLoadingMore && messaging.hasMoreMessages) {
      // Capture pre-pagination scroll metrics BEFORE triggering the load.
      // Used in _onNewMessages to restore visual position after prepend.
      _prePaginationScrollOffset = _scrollController.offset;
      _prePaginationScrollExtent = _scrollController.position.maxScrollExtent;
      setState(() => _isLoadingMoreLocal = true);
      messaging.loadOlderMessages(widget.conversationId);
    }
  }
}
```

- [ ] **Step 8: Add loading indicator at top of messages list + suppress auto-scroll on pagination**

**Part A — Local state fields:**

The three local state fields (`_isLoadingMoreLocal`, `_prePaginationScrollOffset`, `_prePaginationScrollExtent`) were declared in Step 1. Do NOT re-declare them here — only use them as described below.

**Part B — Loading indicator in `build`:**

`ChatDetailScreen` uses `ListView.builder(itemCount: messages.length, itemBuilder: (ctx, i) => ...)`. To insert a loading indicator at the top without breaking index access:

1. Use `_isLoadingMoreLocal` (local field) — NOT `messaging.isLoadingMore`.
2. Change `itemCount: messages.length` to `itemCount: messages.length + (_isLoadingMoreLocal ? 1 : 0)`.
3. In `itemBuilder`, offset indices when `_isLoadingMoreLocal`:
```dart
itemBuilder: (ctx, i) {
  if (_isLoadingMoreLocal && i == 0) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Center(child: CircularProgressIndicator()),
    );
  }
  final msgIndex = _isLoadingMoreLocal ? i - 1 : i;
  // existing message rendering using messages[msgIndex]
},
```

**Part C — Restore scroll position + clear spinner when pagination completes:**

Find `_onNewMessages`. This is the method (or listener callback) that detects `messages.length != _lastMessageCount` and triggers auto-scroll-to-bottom. It is registered as a ChangeNotifier listener in `initState` (look for the `addListener` call). Do NOT create a new `_onNewMessages` method — modify the existing one.

Add this block at the top:
```dart
void _onNewMessages() {
  if (_isLoadingMoreLocal) {
    final messaging = context.read<MessagingProvider>();
    if (!messaging.isLoadingMore) {
      // Pagination just completed: _isLoadingMore was true, now false.
      // Clear spinner and restore the user's visual scroll position.
      setState(() => _isLoadingMoreLocal = false);
      final preOffset = _prePaginationScrollOffset;
      final preExtent = _prePaginationScrollExtent;
      _prePaginationScrollOffset = null;
      _prePaginationScrollExtent = null;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (preOffset == null || preExtent == null) return;
        if (!_scrollController.hasClients) return;
        final newExtent = _scrollController.position.maxScrollExtent;
        // Jump by the delta in maxScrollExtent — keeps user's visual position intact.
        _scrollController.jumpTo(preOffset + (newExtent - preExtent));
      });
      return; // do NOT auto-scroll to bottom after prepend
    }
    // Live message arrived while pagination is in progress.
    // Restore position for this notification and update the baseline extent.
    // Note: if two messages arrive before a single frame renders, the second callback
    // may compute against a stale baseline — minor positional imprecision, acceptable.
    final preOffset = _prePaginationScrollOffset;
    final preExtent = _prePaginationScrollExtent;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (preOffset == null || preExtent == null) return;
      if (!_scrollController.hasClients) return;
      final newExtent = _scrollController.position.maxScrollExtent;
      final delta = newExtent - preExtent;
      _prePaginationScrollOffset = preOffset + delta; // update baseline for next notification
      _prePaginationScrollExtent = newExtent;
      _scrollController.jumpTo(preOffset + delta);
    });
    return; // do NOT auto-scroll to bottom during pagination load
  }
  // Normal auto-scroll logic (existing code) ...
}
```

**Why this is correct — and handles the live-message race:**
`loadOlderMessages()` does NOT call `notifyListeners()`. Notifications only fire from `onMessageHistory` (pagination done: sets `_isLoadingMore = false` before notify) or from `_handleIncomingMessage` (live message: does NOT change `_isLoadingMore`). Checking `!messaging.isLoadingMore` inside the guard distinguishes the two cases:
- Pagination complete → `isLoadingMore == false` → restore position + clear spinner
- Live message during load → `isLoadingMore == true` → restore position + update baseline extent for the next notification

This sidesteps the boolean-flag race entirely. `SchedulerBinding` is in `package:flutter/scheduler.dart` — import if not already present.

- [ ] **Step 9: Write unit tests**

In `frontend/test/providers/messaging_provider_test.dart`:
```dart
test('loadOlderMessages prepends messages and updates _hasMore', () {
  // Seed: simulate onMessageHistory with 50 messages (full page) → _hasMore = true
  // Call loadOlderMessages(conversationId)
  // Assert: isLoadingMore == true
  // Simulate onMessageHistory with 30 older messages (_isPaginationLoad = true)
  // Assert: messages.length == 80 (30 prepended + 50 existing)
  // Assert: hasMoreMessages == false (partial page received)
  // Assert: isLoadingMore == false
});

test('loadOlderMessages is no-op when hasMoreMessages is false', () {
  // hasMoreMessages defaults to false
  // Call loadOlderMessages — isLoadingMore must remain false
  expect(provider.isLoadingMore, false);
  provider.loadOlderMessages(1);
  expect(provider.isLoadingMore, false);
});

test('loadOlderMessages ignores stale response for wrong conversation', () {
  // Set _paginationConversationId = 1 (by calling getMessages(1))
  // Simulate pagination response with conversationId = 2
  // Assert: messages unchanged
});
```

To seed `_hasMore = true`: simulate `onMessageHistory` with exactly `_pageSize` (50) messages for the correct `conversationId`. This naturally sets `_hasMore = true`.

- [ ] **Step 10: Run Flutter tests**
```bash
cd frontend && flutter test
```
Expected: all tests pass.

- [ ] **Step 11: Commit**
```bash
git add frontend/lib/providers/messaging_provider.dart frontend/lib/screens/chat_detail_screen.dart
git commit -m "feat(ux): message pagination — load older messages on scroll-to-top; 3 call sites unified"
```

---

## Summary

| Task | Area | Why it matters |
|---|---|---|
| 1 | JWT invalidation after password change | Stolen token no longer valid after victim changes password |
| 2 | WS rate limits on 7 events | DB cannot be flooded via unthrottled socket events |
| 3 | Magic bytes on avatar upload | Prevents filetype spoofing for unencrypted avatar uploads |
| 4 | Media auth guard + Nginx + Flutter | Unauthenticated download of message blobs prevented |
| 5 | Remove `profilePictureUrl` from JWT | Stale avatar after restart fixed; JWT carries minimal claims |
| 6 | Health check (503 on DB failure) | Docker correctly detects and restarts unhealthy backend |
| 7 | Frontend message pagination | Full conversation history accessible via scroll-to-top |

**Execution order:** Tasks 1, 2, 3, 6 are backend-only and independent — safe to run in parallel. Task 4 spans backend + Nginx + frontend. Task 5 spans backend + frontend. Task 7 is frontend-only. Suggested order: 1 → 2 → 3 → 6 (parallel batch), then 4, then 5, then 7.
