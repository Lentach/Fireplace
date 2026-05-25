# Identity-Key Auth — Design Spec

**Date:** 2026-05-09
**Status:** Approved, **deferred** (2026-05-09)

> **Status note:** The design and the implementation plan
> (`docs/superpowers/plans/2026-05-09-identity-key-auth.md`) are
> complete and ready to execute. They were intentionally **deferred**
> after a pragmatic review:
> - The user-facing problem (PWA auto-logout every 24h) was solved by
>   the Phase 0 hotfix (commit `b851b42`, JWT TTL `24h → 30d`).
> - For the current threat model (small user base, primarily PWA, no
>   high-risk users), the marginal security gain on web is modest
>   (2h vs 30d stolen-token window + per-device revoke), while the
>   refactor cost is high (~30 tasks across 8 PRs, breaking change,
>   single-pod constraint, real production risk).
> - Cheaper higher-ROI security improvements (2FA/TOTP, RS256 JWT
>   signing, audit log with "new login from new device" alert,
>   per-username brute-force throttling) were identified as better
>   next steps for similar effort.
>
> **Re-open this spec when:** native iOS/Android app is launched
> (cryptographic device binding becomes materially valuable),
> "Active Devices" UI is wanted as a product feature, or the threat
> model changes (specific attacker concerns surface).

---

## Problem Statement

PWA users get auto-logged-out after ~24 hours. Root cause: backend issues `expiresIn: '24h'` JWTs (`backend/src/auth/auth.module.ts`) with no refresh mechanism. When the access token expires, the next `GET /users/me` returns 401 and `AuthProvider._loadSavedToken()` clears the stored token, forcing re-login.

When a push notification arrives after the user is logged out, they tap it, the PWA opens, sees no token, and shows the login screen instead of the message — silently breaking the messenger UX.

---

## Goal

Move from bare 24h JWT to a **Signal/Telegram-grade identity-key authentication model** so that:
- A logged-in device stays logged in indefinitely while the keypair is intact
- Stolen session tokens cannot be refreshed (no private key)
- Per-device session management (Active Devices UI, revoke remotely)
- Cryptographic device binding (auth strength matches the existing E2E messaging crypto)

---

## High-Level Architecture

### Three components

```
Client (Flutter)                       Backend (NestJS)
─────────────────                      ─────────────────
AuthIdentityKeyPair      ─────────►    users (unchanged)
  (Ed25519, per-device)                device_sessions  (NEW)
  flutter_secure_storage                 id, userId, authPubKey,
  + SharedPreferences                    deviceLabel, deviceKind,
  (DualStorage)                          expiresAt, lastSeenAt
                                       auth_challenges  (in-memory)
SessionToken (short JWT, 2h)             deviceId → nonce, TTL 60s
  in-memory + persisted ref
```

### Key design decisions

- **Auth keypair is separate from Signal identity key.** Independent rotation, clean domain separation, easier testing.
- **Algorithm: Ed25519.** Standard for signatures, fast, 32-byte keys, native support in `cryptography` (Dart) and Node `crypto`.
- **Session token TTL: 2 hours.** Balances refresh traffic vs stolen-token window. Revocation is **instant** because `IdentityKeySessionGuard` queries `device_sessions` on every request, regardless of TTL.
- **Per-device `device_sessions` table.** Source of truth for active sessions; sliding 90-day expiry. Telegram-style "Active Sessions" UI built on this.
- **Initial credential = username/password (kept).** First-time device login uses password; thereafter, device's identity key takes over silently.
- **Recovery = username/password.** Lost device? Wipe data? Just log in again — generates a fresh keypair, creates a new `device_sessions` row. Old row becomes inert (private key gone).
- **No migration of existing users.** Existing 30d JWTs stop working after deploy; everyone re-logs in once. Acceptable given small user base.

---

## Phased Rollout

### Phase 0 — Hotfix (5 min, deploy immediately)

Bump `expiresIn: '24h'` → `'30d'` in `backend/src/auth/auth.module.ts`. Stops the auto-logout problem during D development. No other changes.

### Phase 1 — Identity-Key Auth (1–2 weeks)

Full implementation of D as described in this spec. After deploy, all users re-login once and never again.

---

## Database Schema

### New table: `device_sessions`

```sql
CREATE TABLE device_sessions (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  auth_pub_key  TEXT         NOT NULL,         -- base64 Ed25519 public key (32B raw)
  device_label  VARCHAR(120) NOT NULL,         -- "Chrome on Windows", "iPhone PWA"
  device_kind   VARCHAR(20)  NOT NULL,         -- web | android | ios | desktop
  expires_at    TIMESTAMPTZ  NOT NULL,         -- sliding 90 days from last_seen_at
  last_seen_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_device_sessions_user_id ON device_sessions(user_id);
CREATE INDEX idx_device_sessions_expires ON device_sessions(expires_at);
-- Note: cleanup cron (sec. below) filters by `expires_at < now() - 30d`.
-- A WHERE-clause partial index referencing NOW() would fail because NOW()
-- is not immutable in PostgreSQL. A plain B-tree index on expires_at is
-- sufficient — cron's filter is applied at query time.
```

### `users` table

Unchanged. The auth public key lives **per device** in `device_sessions`, not on `users`. Source of truth is the device row.

### Cleanup job

Daily cron at 3 AM:
```typescript
@Cron('0 3 * * *')
async cleanupExpiredSessions() {
  await this.sessionRepo.delete({
    expiresAt: LessThan(new Date(Date.now() - 30 * 86400_000)),
  });
}
```

Removes rows that have been expired for 30+ days (90 + 30 = 120 days since last use).

---

## Auth Flows

### Registration (new account)

```
Client:  generate Ed25519 keypair
         POST /auth/register
           { username, password, authPublicKey, deviceLabel, deviceKind }
Backend: INSERT users
         INSERT device_sessions (userId, authPubKey, deviceLabel, ...)
         issue short JWT { sub, username, tag, deviceId, exp: now+2h }
         return { sessionToken, deviceId, user }
Client:  persist privateKey (DualStorage), sessionToken, deviceId
```

### Login (existing account, new device or re-login)

Same as registration but `POST /auth/login`. Each device gets its own `device_sessions` row with its own freshly generated keypair. Old devices are not affected.

### Silent refresh (most common flow — invisible to user)

**Wire format contract:**
- `timestamp` is **Unix epoch in milliseconds** (`Date.now()` / `DateTime.now().millisecondsSinceEpoch`). Both client and server use ms.
- Anti-replay tolerance window: **±60_000 ms**.
- `nonce` is **base64-encoded 32 random bytes**.
- Signed message format: literally `"<nonce>:<timestampMs>"` (UTF-8 bytes).
- Signature: **base64-encoded Ed25519 signature** of the signed message bytes.

```
Client (token <2 min from expiry):
  POST /auth/challenge { deviceId }
Backend:
  generate nonce (32B random base64)
  store (deviceId → nonce) in-memory, TTL 60s
  return { nonce, expiresAt }

Client:
  ts = Date.now()                                     // milliseconds
  message = utf8.encode("${nonce}:${ts}")
  signature = base64(Ed25519.sign(privateKey, message))
  POST /auth/refresh-with-key { deviceId, signature, timestamp: ts }

Backend:
  fetch device_sessions row by deviceId               // 401 if missing
  verify expires_at > now()                           // 401 if expired (and DELETE row)
  nonce = challengeStore.peek(deviceId)               // 401 if missing/expired (>60s)
  if (Math.abs(Date.now() - timestamp) > 60_000) → 401   // anti-old-replay
  message = utf8.encode("${nonce}:${timestamp}")
  if (!Ed25519.verify(authPubKey, signature, message)) → 401
  challengeStore.consume(deviceId)                    // single-use
  UPDATE device_sessions SET last_seen_at=now(), expires_at=now()+90d
  issue fresh session token (2h TTL)
  return { sessionToken }
```

### Normal request (REST/WS)

`Authorization: Bearer <sessionToken>` for REST. `auth.token` for socket.io.

`IdentityKeySessionGuard`:
1. Verify JWT signature + exp (catches local tampering & expiry)
2. SELECT `device_sessions` by `payload.deviceId` (catches remote revocation, instant)
3. Inject `req.user = { id, username, tag, deviceId }`

If 401 mid-request: client triggers refresh flow (single-flight), retries once. Second 401 = hard logout.

### Logout (current device)

```
Client → Backend: POST /auth/logout (Bearer)
Backend: DELETE device_sessions WHERE id = req.user.deviceId
Client:  clear sessionToken + privateKey + deviceId from storage
```

### Remote logout (from another device)

```
Client A → GET /auth/devices  →  list of all devices
Client A → DELETE /auth/devices/:id  (id of Client B)
Backend: DELETE device_sessions WHERE id = ? AND user_id = req.user.id
Client B (next request): 401 → refresh → 401 → hard logout → login screen
```

### Password change

```
POST /auth/reset-password { oldPassword, newPassword }
  bcrypt verify, UPDATE users.password_hash
  DELETE device_sessions WHERE user_id = req.user.id  (all devices)
  → all devices forced to re-login
```

### Account delete

Existing flow + `DELETE device_sessions` (cascade via FK already covers this).

---

## Backend Implementation

### File layout

```
backend/src/auth/
├── auth.module.ts                        ← rewritten
├── auth.controller.ts                    ← rewritten
├── auth.service.ts                       ← extended
├── device-session.entity.ts              ← NEW
├── device-sessions.service.ts            ← NEW
├── auth-challenge.store.ts               ← NEW (in-memory Map)
├── identity-key-session.guard.ts         ← NEW (replaces JwtAuthGuard)
├── strategies/
│   └── session-token.strategy.ts         ← NEW (replaces JwtStrategy)
├── crypto/
│   └── ed25519.verifier.ts               ← NEW (Node `crypto` wrapper)
└── dto/
    ├── register.dto.ts                   ← extended
    ├── login.dto.ts                      ← extended
    ├── challenge.dto.ts                  ← NEW
    └── refresh-with-key.dto.ts           ← NEW
```

### Endpoints

| Endpoint | Body | Response | Guard | Throttle |
|---|---|---|---|---|
| `POST /auth/register` | `{username, password, authPublicKey, deviceLabel, deviceKind}` | `{sessionToken, deviceId, user}` | none | 5 / 60s per IP |
| `POST /auth/login` | `{identifier, password, authPublicKey, deviceLabel, deviceKind}` | `{sessionToken, deviceId, user}` | none | 10 / 60s per IP |
| `POST /auth/challenge` | `{deviceId}` | `{nonce, expiresAt}` | none | **30 / 60s per IP**, **10 / 60s per deviceId** |
| `POST /auth/refresh-with-key` | `{deviceId, signature, timestamp}` | `{sessionToken}` | none (Ed25519 sig is the proof) | **30 / 60s per IP**, **10 / 60s per deviceId** |
| `POST /auth/logout` | — | `204` | `IdentityKeySessionGuard` | global default |
| `GET /auth/devices` | — | `[{id, deviceLabel, deviceKind, lastSeenAt, current}]` | `IdentityKeySessionGuard` | global default |
| `DELETE /auth/devices/:id` | — | `204` | `IdentityKeySessionGuard` | global default |
| `POST /auth/reset-password` | `{oldPassword, newPassword}` | `204` | `IdentityKeySessionGuard` | 5 / 60s per IP |
| `POST /auth/delete-account` | `{password}` | `204` | `IdentityKeySessionGuard` | 5 / 60s per IP |

**Why per-deviceId limits matter for `/auth/challenge`:**

The challenge store keeps one `nonce` per `deviceId`. An attacker who knows a victim's `deviceId` (e.g. exfiltrated from a log) can grief the legitimate client by repeatedly requesting fresh nonces, overwriting the entry the victim is mid-sign for. Per-deviceId throttle (10/min) bounds this attack to ~1 nonce overwrite per 6s, while the victim's normal refresh frequency (every ~2h) is well under the limit. Combined with single-flight on the client side, this is sufficient.

### Session token payload (JWT, 2h)

```json
{
  "sub": 42,
  "username": "kowalski",
  "tag": "1234",
  "deviceId": "uuid-v4",
  "iat": 1234567890,
  "exp": 1234574490
}
```

Signed with existing `JWT_SECRET` (HS256). Future option: RS256 with separate signing/verifying keys.

### Auth challenge store (in-memory, single-instance)

> **Deployment checklist — must be checked before scaling beyond 1 backend pod:**
> 1. The in-memory `AuthChallengeStore` is **not shared** across instances.
> 2. Without sticky sessions, a refresh request can land on a pod that has never seen the nonce → false 401, user logged out spuriously.
> 3. Before deploying behind a load balancer with >1 pod: either
>    (a) enable sticky sessions on `/auth/*` routes, OR
>    (b) replace the `Map`-backed store with Redis (recommended), OR
>    (c) add an `auth_challenges` table with a TTL cleanup cron.
> 4. Until then: keep `docker-compose.yml` at `replicas: 1` and document this in `CLAUDE.md` § "Known Limitations".


```typescript
class AuthChallengeStore {
  private store = new Map<string, { nonce: string; expiresAt: number }>();

  generate(deviceId: string) {
    const nonce = crypto.randomBytes(32).toString('base64');
    const expiresAt = Date.now() + 60_000;
    this.store.set(deviceId, { nonce, expiresAt });
    return { nonce, expiresAt: new Date(expiresAt) };
  }

  peek(deviceId: string): string | null {
    const e = this.store.get(deviceId);
    if (!e || e.expiresAt < Date.now()) return null;
    return e.nonce;
  }

  consume(deviceId: string) {
    this.store.delete(deviceId);
  }
}
```

**Constraint:** single backend instance. Documented in CLAUDE.md. Future migration: swap `Map` for Redis or new `auth_challenges` table.

### Ed25519 verifier (Node `crypto`)

```typescript
import { createPublicKey, verify } from 'node:crypto';

const SPKI_ED25519_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

export class Ed25519Verifier {
  verify(publicKeyB64: string, message: Buffer, signature: Buffer): boolean {
    const rawKey = Buffer.from(publicKeyB64, 'base64');
    if (rawKey.length !== 32) return false;
    const publicKey = createPublicKey({
      key: Buffer.concat([SPKI_ED25519_PREFIX, rawKey]),
      format: 'der',
      type: 'spki',
    });
    return verify(null, message, publicKey, signature);
  }
}
```

### Guard migration — sites that switch from `JwtAuthGuard` → `IdentityKeySessionGuard`

The new guard injects the **same `req.user` shape plus `deviceId`**, so the only change at call sites is the import + decorator. Files to update (verified via grep):

- `backend/src/users/users.controller.ts`
- `backend/src/media/media.controller.ts`
- `backend/src/secret-notes/secret-notes.controller.ts`
- `backend/src/messages/messages.controller.ts`
- `backend/src/auth/auth.controller.ts` (its own protected endpoints)

Old `backend/src/auth/jwt-auth.guard.ts` and `backend/src/auth/strategies/jwt.strategy.ts` are **deleted** in the same change. `JwtModule` stays — it's still used to sign/verify the new short session JWT.

### `req.user` shape (consumed downstream)

```typescript
interface AuthenticatedUser {
  id: number;
  username: string;
  tag: string;
  deviceId: string;        // NEW — was not present in old shape
  profilePictureUrl?: string;  // dropped — fetch via /users/me when needed
}
```

`profilePictureUrl` is intentionally **removed** from the injected user. Old `JwtStrategy` loaded the User entity and copied this field; the new guard avoids the extra DB hit on every request and existing frontend already calls `/users/me` to refresh profile data (per CLAUDE.md "JWT payload no longer carries `profilePictureUrl`").

### Socket.io auth in `ChatGateway`

```typescript
async handleConnection(socket: Socket) {
  const token = socket.handshake.auth?.token;
  if (!token) return socket.disconnect(true);
  try {
    const payload = await this.jwtService.verifyAsync(token);
    const session = await this.sessionsService.findById(payload.deviceId);
    if (!session || session.expiresAt < new Date()) {
      socket.disconnect(true);
      return;
    }
    socket.data.userId = payload.sub;
    socket.data.deviceId = payload.deviceId;
  } catch {
    socket.disconnect(true);
  }
}
```

### Mid-connection token expiry — source of truth

**Client-driven, not server-driven.** Server does **not** poll connection JWT expiry — that would require a per-connection timer for thousands of sockets. Instead:

1. Client persists `_sessionExp` (parsed from JWT `exp`) in `AuthSessionManager`.
2. A single `Timer` in `ConnectionProvider` fires at `_sessionExp - 60s`.
3. On fire: client calls `_sessionManager.forceRefresh()` → on success, calls `socket.disconnect()` then `socket.connect()` (existing `enableForceNew()` path) with the new token.
4. Server-side handler `handleConnection()` runs the same validation as on first connect (`device_sessions` row + JWT verify) — this is the only check that matters.

**Reconnect storm prevention (multi-tab):**
- Same-origin tabs share `SharedPreferences` storage; `AuthSessionManager` checks for newer token in storage before triggering its own refresh. This means tabs naturally serialize on the first one to refresh.
- A `BroadcastChannel('fireplace_auth')` post on successful refresh tells other tabs "use the new token, don't refresh yourself" (web only). Out-of-scope for MVP if it adds complexity — the storage-based serialization is sufficient for the small user base.

### Push notification subscriptions — survive re-login

`fcm_tokens` and `web_push_subscription` rows are keyed by `userId`, not by session. After Phase 1 deploy, when each user re-logs in once:
- Old rows are still in the DB tied to their `userId`.
- Frontend `PushService.initialize(jwtToken)` runs after login and re-registers the FCM/web-push token. If the same token already exists for that user (UNIQUE constraint), it's a no-op upsert.
- **Result:** push notifications continue to work for the same user after the forced re-login. No special migration needed for push.

---

## Frontend Implementation

### File layout

```
frontend/lib/
├── providers/
│   └── auth_provider.dart                ← rewritten
├── services/
│   ├── api_service.dart                  ← extended (auth endpoints)
│   ├── auth_session_manager.dart         ← NEW
│   └── crypto/
│       └── auth_identity_keypair.dart    ← NEW
├── models/
│   └── device_session_model.dart         ← NEW
└── screens/
    └── active_devices_screen.dart        ← NEW
```

### `AuthIdentityKeyPair` (DualStorage)

```dart
class AuthIdentityKeyPair {
  static const _privKey = 'auth_private_key_v1';
  static const _pubKey  = 'auth_public_key_v1';

  final String publicKeyB64;
  final String privateKeyB64;

  // cryptography (^2.7.0) Ed25519 API contract:
  // - newKeyPair() returns SimpleKeyPairData where extractPrivateKeyBytes()
  //   yields the 32-byte SEED (not the 64-byte expanded secret).
  // - newKeyPairFromSeed(seed) accepts that same 32-byte seed and reconstructs
  //   the keypair deterministically.
  // We persist the 32-byte seed and the 32-byte public key (raw), both base64.
  // Verify against package docs in implementation; if API differs, adapt
  // accordingly while preserving "32-byte seed" wire format.
  static Future<AuthIdentityKeyPair> generate() async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final pub = await keyPair.extractPublicKey();
    final seed = await keyPair.extractPrivateKeyBytes();   // 32B seed
    return AuthIdentityKeyPair(
      publicKeyB64: base64Encode(pub.bytes),
      privateKeyB64: base64Encode(seed),                   // store seed
    );
  }

  // _secure() returns a FlutterSecureStorage instance with the same options
  // already used by Signal stores (see signal_stores.dart): WebOptions(dbName: 'FireplaceE2E'),
  // AndroidOptions(encryptedSharedPreferences: true), IOSOptions(accessibility: first_unlock).
  static Future<AuthIdentityKeyPair?> loadFromStorage() async {
    final secure = _secure();
    final prefs = await SharedPreferences.getInstance();
    final priv = await secure.read(key: _privKey) ?? prefs.getString(_privKey);
    final pub  = await secure.read(key: _pubKey)  ?? prefs.getString(_pubKey);
    if (priv == null || pub == null) return null;
    return AuthIdentityKeyPair(publicKeyB64: pub, privateKeyB64: priv);
  }

  Future<void> persist() async {
    final secure = _secure();
    final prefs = await SharedPreferences.getInstance();
    await secure.write(key: _privKey, value: privateKeyB64);
    await secure.write(key: _pubKey,  value: publicKeyB64);
    await prefs.setString(_privKey, privateKeyB64);   // DualStorage backup
    await prefs.setString(_pubKey,  publicKeyB64);
  }

  Future<String> sign(String message) async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(
      base64Decode(privateKeyB64),
    );
    final signature = await algorithm.sign(
      utf8.encode(message),
      keyPair: keyPair,
    );
    return base64Encode(signature.bytes);
  }
}
```

### `AuthSessionManager` (single-flight refresh)

```dart
class AuthSessionManager {
  Completer<String>? _refreshing;
  String? _sessionToken;
  String? _deviceId;
  AuthIdentityKeyPair? _keyPair;
  DateTime? _sessionExp;

  Future<String?> getValidToken() async {
    if (_sessionToken == null || _keyPair == null || _deviceId == null) return null;

    final needsRefresh = _sessionExp == null
        || _sessionExp!.isBefore(DateTime.now().add(const Duration(minutes: 2)));
    if (!needsRefresh) return _sessionToken;

    if (_refreshing != null) return _refreshing!.future;

    _refreshing = Completer<String>();
    try {
      final token = await _doRefresh();
      _sessionToken = token;
      _sessionExp = JwtDecoder.getExpirationDate(token);
      _refreshing!.complete(token);
      return token;
    } catch (e) {
      _refreshing!.completeError(e);
      rethrow;
    } finally {
      _refreshing = null;
    }
  }

  Future<String> _doRefresh() async {
    final challenge = await _api.requestChallenge(_deviceId!);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final sig = await _keyPair!.sign('${challenge['nonce']}:$ts');
    final result = await _api.refreshWithKey(
      deviceId: _deviceId!, signature: sig, timestamp: ts,
    );
    return result['sessionToken'];
  }

  /// Discards cached session token + expiry, preserving deviceId + keyPair.
  /// Single-flight: concurrent callers await the same refresh future.
  /// Throws on refresh failure (caller decides whether to hard-logout).
  Future<String> forceRefresh() async {
    _sessionToken = null;
    _sessionExp = null;
    if (_keyPair == null || _deviceId == null) {
      throw Exception('NO_CREDENTIALS');
    }
    final token = await getValidToken();   // single-flight inside
    if (token == null) throw Exception('REFRESH_FAILED');
    return token;
  }
}
```

### `ApiService` 401 handling

`AuthSessionManager` exposes two distinct operations:
- `getValidToken()` — returns cached token if not near expiry, otherwise refreshes
- `forceRefresh()` — discards **only** the cached `_sessionToken` + `_sessionExp`, then runs refresh; preserves `_deviceId` + `_keyPair` (needed for refresh itself). Single-flight guarded by `Completer`.

```dart
Future<Map<String, dynamic>> fetchMe() async {
  final token = await _sessionManager.getValidToken();
  if (token == null) throw Exception('NOT_AUTHENTICATED');

  var response = await _get('/users/me', token);

  if (response.statusCode == 401) {
    String? newToken;
    try {
      newToken = await _sessionManager.forceRefresh();   // does NOT clear keypair
    } on Exception {
      // Refresh itself failed (revoked session / network) → fall through to hard logout below.
    }
    if (newToken != null) {
      response = await _get('/users/me', newToken);
    }
    if (response.statusCode == 401) throw Exception('SESSION_REVOKED');
  }

  return jsonDecode(response.body);
}
```

`SESSION_REVOKED` is a hard signal — only thrown after the second 401 (i.e., refresh succeeded but the new token is also rejected, or refresh itself returned 401 from `/auth/refresh-with-key`). Only then `AuthProvider` clears keypair + deviceId and shows the login screen.

### `AuthProvider` skeleton

```dart
Future<bool> login(String identifier, String password) async {
  final keyPair = await AuthIdentityKeyPair.generate();
  final result = await _api.login(
    identifier: identifier, password: password,
    authPublicKey: keyPair.publicKeyB64,
    deviceLabel: await _detectDeviceLabel(),
    deviceKind: _detectDeviceKind(),
  );
  await keyPair.persist();
  await _sessionManager.adopt(
    sessionToken: result['sessionToken'],
    deviceId: result['deviceId'],
    keyPair: keyPair,
  );
  _currentUser = UserModel.fromJson(result['user']);
  notifyListeners();
  return true;
}

Future<void> _loadSavedSession() async {
  final keyPair = await AuthIdentityKeyPair.loadFromStorage();
  final secure = AuthIdentityKeyPair.secureStorage();
  final deviceId = await secure.read(key: 'device_id_v1');
  if (keyPair == null || deviceId == null) return;

  await _sessionManager.adopt(
    sessionToken: null, deviceId: deviceId, keyPair: keyPair,
  );

  try {
    final me = await _api.fetchMe();
    _currentUser = UserModel.fromJson(me);
    notifyListeners();
  } on Exception catch (e) {
    if (e.toString().contains('SESSION_REVOKED')) {
      await _clearSession();
      notifyListeners();
    }
  }
}
```

### Device label / kind detection

```dart
String _detectDeviceKind() {
  if (kIsWeb) return 'web';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  return 'desktop';
}

Future<String> _detectDeviceLabel() async {
  if (kIsWeb) {
    final ua = html.window.navigator.userAgent;
    return _shortenUserAgent(ua);   // "Chrome on Windows", "Safari on iPhone"
  }
  final info = DeviceInfoPlugin();
  if (Platform.isAndroid) {
    final a = await info.androidInfo;
    return '${a.manufacturer} ${a.model}';
  }
  if (Platform.isIOS) {
    final i = await info.iosInfo;
    return i.utsname.machine;
  }
  return 'Unknown device';
}
```

### Dependencies

Already present in `pubspec.yaml`:
- `flutter_secure_storage: ^9.2.4`
- `shared_preferences`
- `jwt_decoder`
- `http`
- `device_info_plus: ^11.2.0` (for device labels)
- `libsignal_protocol_dart: ^0.7.4` (for E2E messaging — uses Curve25519/XEd25519 internally; not used for auth)

**New dependency required:**
- `cryptography: ^2.7.0` — Google-maintained pure Ed25519 implementation. Reason: Node backend's built-in `crypto` module supports pure Ed25519 natively; XEd25519 (used by `libsignal_protocol_dart`) would require a custom Node-side implementation. Pure Ed25519 keeps both sides simple and standard.

**Backend (Node) — no new dependencies.** Uses built-in `node:crypto` (`createPublicKey`, `verify`).

---

## Testing Strategy

### Backend (Jest)

| File | Scenarios |
|---|---|
| `auth.service.spec.ts` | register/login with keypair, wrong password, duplicate username |
| `device-sessions.service.spec.ts` | create/find/touch/delete, sliding `expires_at` |
| `auth-challenge.store.spec.ts` | generate unique nonce, consume single-use, expire after 60s |
| `ed25519.verifier.spec.ts` | valid signature, bad signature, wrong key length |
| `auth.controller.spec.ts` | all endpoints |
| `identity-key-session.guard.spec.ts` | no Bearer, invalid JWT, expired session, valid session |

**Critical edge cases:**
1. Refresh with non-existent nonce → 401
2. Refresh with already-consumed nonce → 401 (replay)
3. Refresh with nonce older than 60s → 401
4. Refresh with timestamp >60s from now → 401 (anti-old-replay)
5. Refresh with valid signature but wrong `deviceId` → 401
6. Refresh when `device_sessions.expires_at < now` → 401 + DELETE row
7. Logout: removes only own `device_sessions`, not others'
8. `DELETE /devices/:id`: only owner can delete
9. Concurrent refresh same `deviceId` → second waits for first
10. Reset-password: removes all `device_sessions` for user

### Frontend (Flutter test)

| File | Scenarios |
|---|---|
| `auth_identity_keypair_test.dart` | generate, persist, loadFromStorage (secure & prefs fallback), sign |
| `auth_session_manager_test.dart` | single-flight (5 concurrent → 1 refresh), 401 retry, hard logout on second 401, expiry calculations |
| `auth_provider_test.dart` | login flow, `_loadSavedSession` (with & without keypair), logout, deleteAccount |

**Critical edge cases:**
1. 10 parallel requests with expired token → only 1 refresh fires, all 10 get new token
2. Storage corruption (private key gone, public key remains) → treat as logged out
3. Network down during refresh → all pending requests get NetworkException, session preserved, next request retries refresh
4. Sign-out from other device + this device sends refresh → 401 → hard logout
5. (Web only) iOS Safari ITP cleared IndexedDB but localStorage survived → DualStorage fallback works

### Manual E2E

1. Register → Active Devices shows 1 row
2. Login on another browser → 2 rows
3. Remote-logout the second from the first → second browser shows login at next refresh (max 2h)
4. Change password → both browsers must re-login
5. Leave app open 1h → use a feature → works (silent refresh in background)
6. Leave app closed 89 days → open → works (sliding window)
7. Leave app closed 100 days → open → login screen (sliding window expired)

### Additional cases added during spec review

| Case | Scenario | Expected |
|---|---|---|
| **Clock skew (client ahead)** | Client clock 90s in future, signs `nonce:ts+90000` | Server rejects with 401 (timestamp out of window). User sees "session error, please re-login" |
| **Clock skew (client behind)** | Client clock 90s in past | Same — 401 |
| **Phase 0 → Phase 1 smoke test** | Old client with 30d JWT hits new backend | All `/users/me`, `/messages/*`, `/media/*` return 401 cleanly (no 500). Frontend shows login screen — does NOT crash on missing endpoints |
| **synchronize entity match** | Run `npm test:e2e` against fresh PostgreSQL | TypeORM `synchronize: true` (non-prod) auto-creates `device_sessions` table. Production still requires manual migration script (or one-time `synchronize` on first deploy with explicit operator action). Document migration command in `backend/scripts/` |
| **Multi-tab refresh** | 3 browser tabs of same user; force refresh by clearing in-memory `_sessionExp` on tab #1 | Only tab #1 hits `/auth/refresh-with-key`. Tabs #2/#3 read newer token from `SharedPreferences` on next request, no extra refreshes |
| **Challenge griefing** | Attacker spams `/auth/challenge` for victim's `deviceId` | Per-deviceId throttle (10/60s) returns 429 after 10 calls. Victim's legitimate refresh succeeds within window |
| **Empty/malformed signature** | Client sends `signature: ""` or non-base64 garbage | Backend returns 401 (verifier returns false), no 500 |
| **DB row tampering hardening** | Manually swap `auth_pub_key` on a `device_sessions` row | Next legitimate refresh fails (signature won't verify against new key). Original device must re-login. Acceptable threat model: DB write access = full compromise anyway |

---

## Trade-offs and Future Work

### Accepted limitations

- **Single backend instance** assumed (in-memory challenge store). Documented as explicit constraint with a deployment checklist (see § "Auth challenge store"). Migration path: swap `Map` for Redis or DB table when scaling out.
- **HS256 JWT for session token.** Future hardening: switch to RS256/EdDSA with split signing/verifying keys.
- **No theft detection.** Refresh-token rotation provides this; identity-key auth makes it less critical because stolen session token can't refresh, but token can still be used until 2h expiry. If higher security needed later, add nonce reuse detection: if nonce was already consumed by a different signature in last few minutes, alert and revoke session.
- **No biometric protection of private key on mobile.** `flutter_secure_storage` uses Keychain/Keystore by default which can be biometric-protected, but enabling that adds UX friction (TouchID/FaceID prompt on every refresh). Out of scope for MVP.
- **Guard does not pin `auth_pub_key` to JWT payload.** `IdentityKeySessionGuard` validates JWT signature + verifies the `device_sessions` row exists for `payload.deviceId`. It does **not** check that the row's current `auth_pub_key` matches a key fingerprint in the JWT payload. Implication: if an attacker had DB write access and swapped `auth_pub_key`, any in-flight session token would still be accepted until the next refresh (~2h max). This is acceptable because DB write access = total compromise anyway. Optional hardening: include `keyHash = sha256(auth_pub_key).slice(0,8)` in the JWT payload, guard rejects on mismatch. **Defer to future iteration.**

### Future enhancements

- Add `revokedAt` column to `device_sessions` for soft-delete + audit log
- Add IP / geo info to `device_sessions` for "Login from new location" alerts
- Add optional QR-code login flow (scan QR from logged-in device to add new device without password)
- Migrate session token from JWT to opaque server-side session ID (eliminates JWT_SECRET as single point of failure)

---

## Open Questions Resolved During Brainstorming

| Question | Decision |
|---|---|
| Reuse Signal identity key vs separate auth keypair? | **Separate** — independent rotation, clean separation |
| Algorithm? | **Ed25519** — modern, fast, small keys, native Node `crypto` support |
| Session token TTL? | **2 hours** — balances refresh traffic vs stolen-token window |
| Migration of existing 30d JWTs? | **None** — small user base, everyone re-logs in once after deploy |
| Phase 0 hotfix needed? | **Yes** — bump to 30d JWT during D development |
| Where to store private key on web? | **DualStorage** — `flutter_secure_storage` (WebCrypto+IndexedDB) + `SharedPreferences` (localStorage) fallback |
| Active Devices UI in MVP? | **Yes** — minimum: list + remote-logout |
| In-memory challenge store vs DB? | **In-memory** — single backend instance now, documented constraint with deployment checklist |

## Decisions added during spec review

| Question | Decision |
|---|---|
| Wire format for `timestamp`? | **Unix milliseconds** end-to-end (Dart: `DateTime.now().millisecondsSinceEpoch`, Node: `Date.now()`); ±60_000 ms tolerance |
| Wire format for `nonce`, `signature`? | **Base64**, raw 32B nonce + raw 64B Ed25519 signature |
| Signed message format? | Literal `"<nonce>:<timestampMs>"` UTF-8 bytes |
| `partial WHERE expires_at < NOW()` index? | **Removed** — non-immutable predicate fails. Plain B-tree on `expires_at` + cron filters at query time |
| `ApiService.invalidate()` semantics on 401? | **Renamed to `forceRefresh()`**, clears only `_sessionToken` + `_sessionExp`, preserves `_deviceId` + `_keyPair` |
| Rate limiting on `/auth/challenge` + `/auth/refresh-with-key`? | **Per-IP + per-deviceId** throttling, 10-30/min |
| Mid-connection token expiry handler? | **Client-driven** via `Timer` based on JWT `exp`; server does not poll |
| Multi-tab refresh storm? | Storage-based serialization (sufficient for MVP); BroadcastChannel optional |
| Push notifications after re-login? | **Survive automatically** — `fcm_tokens` and `web_push_subscription` keyed by `userId`, frontend re-registers token on next login (idempotent upsert) |
| Pin `auth_pub_key` hash in JWT payload? | **Defer** — DB write access = full compromise; not worth the extra payload byte for MVP |
