# Backend Release Blockers — Implementation Plan

> Executed inline this session on branch `fix/backend-release-blockers` (off `master`). Steps use `- [ ]`.

**Goal:** Flip the backend from NO-GO to GO for app release by fixing the verified release blockers and two cheap security wins, with regression tests so they can't silently revert.

**Architecture:** Small, surgical backend changes only. HTTP throttling becomes effective by applying `ThrottlerGuard` per HTTP controller (NOT a global `APP_GUARD` — that would also fire on the WebSocket gateway and crash on `res.header()`; WS already uses `WsThrottlerGuard`). Secret-notes gets a per-route CSP + nonce so its inline reveal script runs under helmet. WS handshake replicates the HTTP `passwordChangedAt` invalidation. Plus `messageType` enum validation and user-scoped FCM-token delete.

**Tech Stack:** NestJS 11, @nestjs/throttler 6, class-validator, helmet 8, jest.

---

## Findings addressed
- BLOCKER: HTTP rate limits inert (`ThrottlerGuard` never registered) — `auth/users/media/secret-notes` controllers (verified: `@Throttle` present, no guard).
- SHOULD-FIX: Secret Notes reveal broken in prod (helmet CSP blocks inline `onclick`+`<script>`) — `secret-notes.controller.ts:96,108`.
- SHOULD-FIX: WS handshake skips `passwordChangedAt` — `chat.gateway.ts:88`.
- NICE: `messageType` not enum-validated (`chat/dto/chat.dto.ts`); `DELETE /users/fcm-token` not user-scoped (`users.controller.ts:147`).
- BLOCKER (ops, not code): verify prod schema under `synchronize:OFF` — documented as a VM verification step (Task 6).

## File Structure
- Modify `backend/src/auth/auth.controller.ts`, `backend/src/users/users.controller.ts`, `backend/src/media/media.controller.ts`, `backend/src/secret-notes/secret-notes.controller.ts` — add `@UseGuards(ThrottlerGuard)` (class level).
- Create `backend/src/throttler-guard.applied.spec.ts` — regression test asserting the guard is applied.
- Modify `backend/src/secret-notes/secret-notes.controller.ts` — per-route CSP + nonce, `addEventListener` instead of `onclick`.
- Modify `backend/src/chat/chat.gateway.ts` — `passwordChangedAt` check in `handleConnection`.
- Modify `backend/src/chat/dto/chat.dto.ts` — `@IsIn` on `messageType`.
- Modify `backend/src/fcm-tokens/fcm-tokens.service.ts` + `backend/src/users/users.controller.ts` — user-scoped FCM delete.

---

### Task 1: Make HTTP rate limiting effective (BLOCKER)

- [ ] **Step 1:** `auth.controller.ts` — add import and class-level guard.

```ts
import { Controller, Post, Body, HttpCode, HttpStatus, UseGuards } from '@nestjs/common';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
// ...
@Controller('auth')
@UseGuards(ThrottlerGuard)
export class AuthController {
```

- [ ] **Step 2:** `users.controller.ts` — `UseGuards` already imported; add `ThrottlerGuard` to the throttler import and the class decorator. Note: routes already use `@UseGuards(JwtAuthGuard)` at method level; class-level `@UseGuards(ThrottlerGuard)` composes fine (both run).

```ts
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
// ...
@Controller('users')
@UseGuards(ThrottlerGuard)
export class UsersController {
```

- [ ] **Step 3:** `media.controller.ts` — `UseGuards` already imported; add `ThrottlerGuard` to import and class decorator.

```ts
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
// ...
@Controller('media')
@UseGuards(ThrottlerGuard)
export class MediaController {
```

- [ ] **Step 4:** `secret-notes.controller.ts` — add `ThrottlerGuard` import + class guard, and throttle the public reveal/create.

```ts
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
// ...
@Controller()
@UseGuards(ThrottlerGuard)
export class SecretNotesController {
// on createNote: @Throttle({ default: { limit: 20, ttl: 3600000 } })
// on revealNote (public, token-guessable): @Throttle({ default: { limit: 30, ttl: 60000 } })
// on getNotePage (public): @Throttle({ default: { limit: 60, ttl: 60000 } })
```

- [ ] **Step 5:** Create `backend/src/throttler-guard.applied.spec.ts` — regression test (no DB).

```ts
import { ThrottlerGuard } from '@nestjs/throttler';
import { AuthController } from './auth/auth.controller';
import { UsersController } from './users/users.controller';
import { MediaController } from './media/media.controller';
import { SecretNotesController } from './secret-notes/secret-notes.controller';

describe('ThrottlerGuard is applied to rate-limited HTTP controllers', () => {
  it.each([
    ['AuthController', AuthController],
    ['UsersController', UsersController],
    ['MediaController', MediaController],
    ['SecretNotesController', SecretNotesController],
  ])('%s has ThrottlerGuard', (_name, ctrl) => {
    const guards = Reflect.getMetadata('__guards__', ctrl) || [];
    expect(guards).toContain(ThrottlerGuard);
  });
});
```

- [ ] **Step 6:** Run `cd backend && npx jest --config jest.config.json src/throttler-guard.applied.spec.ts` → PASS.

### Task 2: Secret Notes — per-route CSP + nonce so reveal works under helmet (SHOULD-FIX)

- [ ] **Step 1:** In `secret-notes.controller.ts`, generate a nonce per HTML response and set a route-scoped CSP that overrides helmet's global one (Express `setHeader` replaces). Add `import { randomBytes } from 'crypto';`.

```ts
private setNoteCsp(res: Response, nonce: string) {
  res.setHeader(
    'Content-Security-Policy',
    `default-src 'self'; script-src 'nonce-${nonce}'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'`,
  );
}
```

- [ ] **Step 2:** In `getNotePage`, build a nonce, set CSP, and pass the nonce into `landingPage`:

```ts
const nonce = randomBytes(16).toString('base64');
this.setNoteCsp(res, nonce);
res.send(this.landingPage(token, remainingLabel, nonce));
```

- [ ] **Step 3:** In `landingPage(token, remaining, nonce)`: change the button to `<button class="btn" id="revealBtn">🔓 Reveal &amp; Destroy</button>` (remove inline `onclick`), tag the script `<script nonce="${nonce}">`, and replace the inline handler with `document.getElementById('revealBtn').addEventListener('click', reveal);` at the end of the script (script-src-attr blocks inline `onclick` even with a nonce — must use addEventListener).

- [ ] **Step 4:** Apply `setNoteCsp` to the not-found/destroyed HTML responses too (style-src 'unsafe-inline' keeps their styling; they have no script).

- [ ] **Step 5:** Existing `secret-notes.controller.spec.ts` still passes; add an assertion that `getNotePage` sets a `Content-Security-Policy` header containing `nonce-` and that the returned HTML contains `addEventListener` and no `onclick=`.

- [ ] **Step 6:** `npx jest --config jest.config.json src/secret-notes/secret-notes.controller.spec.ts` → PASS.

### Task 3: WS handshake honors `passwordChangedAt` (SHOULD-FIX)

- [ ] **Step 1:** In `chat.gateway.ts` `handleConnection`, after `const user = await this.usersService.findById(payload.sub);` and the null check, add:

```ts
if (user.passwordChangedAt) {
  const changedAtSeconds = Math.floor(user.passwordChangedAt.getTime() / 1000);
  if (typeof payload.iat === 'number' && payload.iat <= changedAtSeconds) {
    client.disconnect();
    return;
  }
}
```
(`jwtService.verify` returns `iat`; `findById` already returns the `User` entity which includes `passwordChangedAt`.)

- [ ] **Step 2:** Add/extend `chat.gateway.spec.ts`: a connection with a token whose `iat` is before `passwordChangedAt` → `client.disconnect()` called, `onlineUsers` not set.

- [ ] **Step 3:** `npx jest --config jest.config.json src/chat/chat.gateway.spec.ts` → PASS.

### Task 4: messageType enum validation + user-scoped FCM delete (NICE)

- [ ] **Step 1:** `chat/dto/chat.dto.ts` — on `SendMessageDto.messageType`, add `@IsIn(['text','image','voice','file', ...])` matching the `MessageType` enum values (import the enum and use `@IsIn(Object.values(MessageType))`). Keep it optional if currently optional.

- [ ] **Step 2:** `fcm-tokens.service.ts` — add:

```ts
async removeByTokenForUser(userId: number, token: string): Promise<void> {
  await this.repo.delete({ userId, token });
}
```

- [ ] **Step 3:** `users.controller.ts` `removeFcmToken` — call `this.fcmTokensService.removeByTokenForUser(req.user.id, dto.token);`.

- [ ] **Step 4:** Run any existing fcm/chat dto specs; add a dto spec asserting an invalid `messageType` fails validation.

### Task 5: Full suite + lint

- [ ] **Step 1:** `cd backend && npm test` → all suites pass (was ~310; new tests added).
- [ ] **Step 2:** `npx tsc -p tsconfig.build.json --noEmit` (or `npm run build`) → compiles clean.

### Task 6: Prod schema verification (BLOCKER 2 — ops, document only)

- [ ] **Step 1:** Document in the PR / deploy notes the VM command to confirm schema under `synchronize:OFF`:

```bash
docker compose -f docker-compose.prod.yml exec db psql -U postgres -d chatdb -c "\dt" \
  -c "\d refresh_tokens" -c "\d secret_notes" \
  -c "select column_name from information_schema.columns where table_name='messages';"
```
Confirm `refresh_tokens`, `secret_notes`, and the `messages` columns `disappearAfterSeconds`/`reactions`/`pinnedMessageId`/`pinnedAt`/`pinnedByUserId` + `users.passwordChangedAt` + index `idx_messages_conv_created` exist. If any missing, run the documented ALTER/CREATE from `backend/CLAUDE.md` before release.

---

## Self-Review
- **Coverage:** throttler BLOCKER (T1), secret-notes CSP (T2), WS passwordChangedAt (T3), messageType + fcm scope (T4), suite (T5), schema (T6). ✓
- **Placeholders:** none — concrete code per step.
- **WS-safety:** throttling applied per-HTTP-controller, not global APP_GUARD → gateway untouched (no double-guard / res.header crash). ✓
- **Consistency:** `ThrottlerGuard` imported from `@nestjs/throttler` everywhere; `setNoteCsp`/`landingPage(token, remaining, nonce)` signatures consistent. ✓
- **Risk:** class-level `@UseGuards(ThrottlerGuard)` composes with method-level `@UseGuards(JwtAuthGuard)` (both run, order independent). CSP override is per-response, scoped to /note routes; global API CSP unchanged.

---

## Review incorporated (one-agent review) — revisions BEFORE implementation

**P0 (release-gating) — client-IP attribution.** nginx sets `X-Real-IP $remote_addr` only (verified `frontend/nginx.conf`), and `main.ts` never sets trust-proxy, so throttler's default `req.ip` = nginx → ALL clients share one bucket → global login lockout. **Revised Task 1** (supersedes per-controller `@UseGuards`):
- Create `backend/src/common/http-throttler.guard.ts`: `HttpThrottlerGuard extends ThrottlerGuard` that (a) `canActivate` returns `true` for non-`http` contexts (so it never runs on the WS gateway / no `res.header` crash; `WsThrottlerGuard` still guards WS), and (b) overrides `getTracker` to use `x-real-ip` (falls back to `x-forwarded-for[0]`, then `req.ip`).
- Register globally in `app.module.ts` `providers: [{ provide: APP_GUARD, useClass: HttpThrottlerGuard }]` (DI resolves: `ThrottlerModule.forRoot` is global). This activates every HTTP `@Throttle` + the 100/15min default across all endpoints, with correct per-client IP, and is certain to wire up.
- `main.ts`: `app.set('trust proxy', 1)` (correct `req.ip` fallback).
- Test: `backend/src/common/http-throttler.guard.spec.ts` — `canActivate` skips a `ws` context (returns true); `getTracker` returns the `x-real-ip` value. (No DB; construct with typed stubs via `as unknown as <Type>`, never `as any` — `Reflector` real, storage/options stubbed.)
- DEPLOY NOTE: the **host** nginx (`/etc/nginx/sites-enabled/fireplace`) must also set `proxy_set_header X-Real-IP $remote_addr;` on the proxied locations, else the tracker falls back to `req.ip` (127.0.0.1) and limits go global again. Verify during deploy.
- The 4 HTTP controllers no longer need `@UseGuards(ThrottlerGuard)` (global guard covers them).

**P1 — secret-notes test stub.** Task 2: add `res.setHeader = jest.fn().mockReturnValue(res);` to `mockRes()` in `secret-notes.controller.spec.ts` (else the new `setNoteCsp` throws and existing `getNotePage` tests fail).

**P1 — messageType enum is UPPERCASE.** Task 4: use `@IsIn(Object.values(MessageType))` importing `MessageType` from `../../messages/message.entity` (values `TEXT/PING/IMAGE/VOICE/GIF/FILE`). NEVER the lowercase literal — it would reject all real messages. Keep `@IsOptional()`.

**P2 — FCM repo member.** Task 4: `removeByTokenForUser` uses `this.fcmTokenRepo.delete({ userId, token })` (member is `fcmTokenRepo`, not `repo`).
