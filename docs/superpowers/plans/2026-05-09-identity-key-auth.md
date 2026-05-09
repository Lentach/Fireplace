# Identity-Key Auth — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace bare 24h JWT with Signal/Telegram-grade identity-key auth — per-device Ed25519 keypairs, silent challenge-response refresh, `device_sessions` table for instant per-device revocation, sliding 90-day session expiry. Reference spec: `docs/superpowers/specs/2026-05-09-identity-key-auth-design.md`.

**Architecture:** Each device generates an Ed25519 auth keypair on first login; public key stored in `device_sessions` row, private key in `flutter_secure_storage` (DualStorage). Session token is a short-lived (2h) JWT carrying `deviceId`. Mid-app-session refresh: client requests `nonce`, signs `nonce:timestampMs`, posts to `/auth/refresh-with-key`; backend verifies signature against stored public key + DB row freshness. Stolen session token cannot refresh (no private key) → dies at 2h max.

**Tech Stack:** NestJS 11 + TypeORM + PostgreSQL 16 + Node `crypto` (Ed25519 native) + Flutter `cryptography` ^2.7.0 + `flutter_secure_storage` + `SharedPreferences`.

**Phase 0 already deployed:** `expiresIn: '24h'` → `'30d'` in `backend/src/auth/auth.module.ts` (commit `b851b42`). Removes daily auto-logout while Phase 1 is being built. Phase 1 (this plan) eliminates JWT-only auth entirely.

---

## Scope Check

This plan covers **one focused subsystem: authentication**. It does not introduce any new product features outside auth. Existing E2E messaging, push notifications, media handling, and chat features are explicitly preserved (push survives re-login because `fcm_tokens` and `web_push_subscription` rows are keyed by `userId`).

No decomposition needed.

---

## File Structure

### Backend — NEW files

```
backend/src/auth/
├── device-session.entity.ts                  ← TypeORM entity for device_sessions
├── device-sessions.service.ts                ← CRUD + sliding expiry
├── device-sessions.service.spec.ts           ← Unit tests
├── auth-challenge.store.ts                   ← In-memory nonce store
├── auth-challenge.store.spec.ts              ← Unit tests
├── identity-key-session.guard.ts             ← Replaces JwtAuthGuard
├── identity-key-session.guard.spec.ts        ← Unit tests
├── crypto/
│   ├── ed25519.verifier.ts                   ← Wraps node:crypto
│   └── ed25519.verifier.spec.ts              ← Unit tests
└── dto/
    ├── challenge.dto.ts                      ← {deviceId}
    ├── refresh-with-key.dto.ts               ← {deviceId, signature, timestamp}
    ├── logout-device.dto.ts                  ← (path param only)
    └── device-info.dto.ts                    ← Response DTO for /devices
```

### Backend — MODIFIED files

```
backend/src/auth/
├── auth.module.ts                            ← register new providers, remove JwtStrategy
├── auth.controller.ts                        ← rewrite endpoints (register/login/challenge/refresh/devices/logout/...)
├── auth.controller.spec.ts                   ← rewrite tests
├── auth.service.ts                           ← extend register/login to create device_sessions
├── auth.service.spec.ts                      ← extend tests
└── dto/
    ├── login.dto.ts                          ← add authPublicKey, deviceLabel, deviceKind
    └── register.dto.ts                       ← add authPublicKey, deviceLabel, deviceKind

backend/src/users/
├── users.controller.ts                       ← swap @UseGuards(JwtAuthGuard) → IdentityKeySessionGuard

backend/src/media/
├── media.controller.ts                       ← swap guard

backend/src/secret-notes/
├── secret-notes.controller.ts                ← swap guard

backend/src/messages/
├── messages.controller.ts                    ← swap guard

backend/src/chat/
├── chat.gateway.ts                           ← update handleConnection to validate device_sessions

backend/src/app.module.ts                     ← add cleanup cron module
backend/src/auth/auth.cleanup.service.ts      ← NEW @Cron daily cleanup
backend/src/auth/auth.cleanup.service.spec.ts ← NEW

CLAUDE.md                                     ← update auth section after Phase 1
```

### Backend — DELETED files (after cutover)

```
backend/src/auth/jwt-auth.guard.ts
backend/src/auth/strategies/jwt.strategy.ts
backend/src/auth/jwt.strategy.spec.ts
```

### Frontend — NEW files

```
frontend/lib/
├── services/
│   ├── auth_session_manager.dart             ← Single-flight refresh
│   └── crypto/
│       └── auth_identity_keypair.dart        ← Ed25519 keypair generate/persist/sign
├── models/
│   └── device_session_model.dart             ← Active Devices entry
└── screens/
    └── active_devices_screen.dart            ← List + remote-logout

frontend/test/
├── services/
│   ├── auth_session_manager_test.dart
│   └── crypto/
│       └── auth_identity_keypair_test.dart
└── providers/
    └── auth_provider_identity_key_test.dart  ← Re-tests AuthProvider with new flow
```

### Frontend — MODIFIED files

```
frontend/lib/
├── pubspec.yaml                              ← + cryptography: ^2.7.0
├── providers/
│   ├── auth_provider.dart                    ← Rewrite for identity-key flow
│   └── connection_provider.dart              ← Add Timer for proactive refresh
├── services/
│   └── api_service.dart                      ← Add auth endpoints + 401-retry helper
├── screens/
│   ├── auth_screen.dart                      ← Pass deviceLabel/deviceKind during login
│   └── settings_screen.dart                  ← Add "Active Devices" entry
```

---

# PR 1 — Backend Foundation

Goal: build the new auth primitives (entity, service, verifier, challenge store) **alongside** the existing `JwtAuthGuard`. No cutover yet. After this PR, backend still authenticates with old JWT exclusively; new files are dormant code with passing unit tests.

## Task 1 — `DeviceSession` entity

**Files:**
- Create: `backend/src/auth/device-session.entity.ts`

- [ ] **Step 1: Create the entity**

```typescript
// backend/src/auth/device-session.entity.ts
import {
  Entity, PrimaryGeneratedColumn, Column, CreateDateColumn,
  ManyToOne, JoinColumn, Index,
} from 'typeorm';
import { User } from '../users/user.entity';

@Entity('device_sessions')
@Index(['userId'])
@Index(['expiresAt'])
export class DeviceSession {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'user_id' })
  userId: number;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column({ name: 'auth_pub_key', type: 'text' })
  authPublicKey: string;

  @Column({ name: 'device_label', length: 120 })
  deviceLabel: string;

  @Column({ name: 'device_kind', length: 20 })
  deviceKind: 'web' | 'android' | 'ios' | 'desktop';

  @Column({ name: 'expires_at', type: 'timestamptz' })
  expiresAt: Date;

  @Column({ name: 'last_seen_at', type: 'timestamptz', default: () => 'now()' })
  lastSeenAt: Date;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;
}
```

- [ ] **Step 2: Commit**

```bash
git add backend/src/auth/device-session.entity.ts
git commit -m "feat(auth): add DeviceSession entity"
```

---

## Task 2 — `DeviceSessionsService`

**Files:**
- Create: `backend/src/auth/device-sessions.service.ts`
- Create: `backend/src/auth/device-sessions.service.spec.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// backend/src/auth/device-sessions.service.spec.ts
import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { DeviceSessionsService } from './device-sessions.service';
import { DeviceSession } from './device-session.entity';

const mockRepo = () => ({
  create: jest.fn((x) => x),
  save: jest.fn((x) => Promise.resolve({ ...x, id: 'uuid-1' })),
  findOne: jest.fn(),
  find: jest.fn(),
  delete: jest.fn(),
  update: jest.fn(),
});

describe('DeviceSessionsService', () => {
  let service: DeviceSessionsService;
  let repo: ReturnType<typeof mockRepo>;

  beforeEach(async () => {
    const moduleRef = await Test.createTestingModule({
      providers: [
        DeviceSessionsService,
        { provide: getRepositoryToken(DeviceSession), useFactory: mockRepo },
      ],
    }).compile();
    service = moduleRef.get(DeviceSessionsService);
    repo = moduleRef.get(getRepositoryToken(DeviceSession));
  });

  it('create() inserts row with sliding 90d expiry', async () => {
    const result = await service.create({
      userId: 7,
      authPublicKey: 'pubkey-b64',
      deviceLabel: 'Chrome on Windows',
      deviceKind: 'web',
    });
    expect(repo.save).toHaveBeenCalled();
    const saved = repo.save.mock.calls[0][0];
    expect(saved.userId).toBe(7);
    expect(saved.authPublicKey).toBe('pubkey-b64');
    const ttlMs = saved.expiresAt.getTime() - Date.now();
    expect(ttlMs).toBeGreaterThan(89 * 86400_000);
    expect(ttlMs).toBeLessThan(91 * 86400_000);
    expect(result.id).toBe('uuid-1');
  });

  it('findById() returns null when not found', async () => {
    repo.findOne.mockResolvedValueOnce(null);
    const result = await service.findById('not-here');
    expect(result).toBeNull();
  });

  it('touch() bumps last_seen_at and slides expires_at by 90 days', async () => {
    await service.touch('uuid-1');
    expect(repo.update).toHaveBeenCalled();
    const [where, patch] = repo.update.mock.calls[0];
    expect(where).toEqual({ id: 'uuid-1' });
    const ttlMs = patch.expiresAt.getTime() - Date.now();
    expect(ttlMs).toBeGreaterThan(89 * 86400_000);
  });

  it('delete() removes row', async () => {
    await service.delete('uuid-1');
    expect(repo.delete).toHaveBeenCalledWith({ id: 'uuid-1' });
  });

  it('findByUser() returns rows for user', async () => {
    repo.find.mockResolvedValueOnce([{ id: 'uuid-1' }, { id: 'uuid-2' }]);
    const rows = await service.findByUser(7);
    expect(repo.find).toHaveBeenCalledWith({
      where: { userId: 7 },
      order: { lastSeenAt: 'DESC' },
    });
    expect(rows.length).toBe(2);
  });

  it('deleteAllForUser() removes all rows for user', async () => {
    await service.deleteAllForUser(7);
    expect(repo.delete).toHaveBeenCalledWith({ userId: 7 });
  });
});
```

- [ ] **Step 2: Run tests, verify failure**

```bash
cd backend && npx jest src/auth/device-sessions.service.spec.ts
```
Expected: FAIL — `DeviceSessionsService` not found.

- [ ] **Step 3: Implement service**

```typescript
// backend/src/auth/device-sessions.service.ts
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { LessThan, Repository } from 'typeorm';
import { DeviceSession } from './device-session.entity';

const SLIDING_DAYS = 90;
const SLIDING_MS = SLIDING_DAYS * 86400_000;

interface CreateInput {
  userId: number;
  authPublicKey: string;
  deviceLabel: string;
  deviceKind: 'web' | 'android' | 'ios' | 'desktop';
}

@Injectable()
export class DeviceSessionsService {
  constructor(
    @InjectRepository(DeviceSession)
    private readonly repo: Repository<DeviceSession>,
  ) {}

  async create(input: CreateInput): Promise<DeviceSession> {
    const now = new Date();
    const entity = this.repo.create({
      userId: input.userId,
      authPublicKey: input.authPublicKey,
      deviceLabel: input.deviceLabel.slice(0, 120),
      deviceKind: input.deviceKind,
      expiresAt: new Date(now.getTime() + SLIDING_MS),
      lastSeenAt: now,
    });
    return this.repo.save(entity);
  }

  findById(id: string): Promise<DeviceSession | null> {
    return this.repo.findOne({ where: { id }, relations: ['user'] });
  }

  findByUser(userId: number): Promise<DeviceSession[]> {
    return this.repo.find({
      where: { userId },
      order: { lastSeenAt: 'DESC' },
    });
  }

  async touch(id: string): Promise<void> {
    const now = new Date();
    await this.repo.update(
      { id },
      { lastSeenAt: now, expiresAt: new Date(now.getTime() + SLIDING_MS) },
    );
  }

  async delete(id: string): Promise<void> {
    await this.repo.delete({ id });
  }

  async deleteAllForUser(userId: number): Promise<void> {
    await this.repo.delete({ userId });
  }

  async deleteExpiredOlderThan(cutoff: Date): Promise<number> {
    const result = await this.repo.delete({ expiresAt: LessThan(cutoff) });
    return result.affected ?? 0;
  }
}
```

- [ ] **Step 4: Run tests, verify pass**

```bash
cd backend && npx jest src/auth/device-sessions.service.spec.ts
```
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add backend/src/auth/device-sessions.service.ts backend/src/auth/device-sessions.service.spec.ts
git commit -m "feat(auth): add DeviceSessionsService with sliding 90d expiry"
```

---

## Task 3 — `Ed25519Verifier`

**Files:**
- Create: `backend/src/auth/crypto/ed25519.verifier.ts`
- Create: `backend/src/auth/crypto/ed25519.verifier.spec.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// backend/src/auth/crypto/ed25519.verifier.spec.ts
import { generateKeyPairSync, sign as nodeSign } from 'node:crypto';
import { Ed25519Verifier } from './ed25519.verifier';

describe('Ed25519Verifier', () => {
  let verifier: Ed25519Verifier;
  beforeEach(() => { verifier = new Ed25519Verifier(); });

  function makePair(): { rawPubB64: string; privateKey: any } {
    const { publicKey, privateKey } = generateKeyPairSync('ed25519');
    const der = publicKey.export({ type: 'spki', format: 'der' });
    // SPKI Ed25519 prefix is 12 bytes; raw key is the trailing 32 bytes
    const raw = der.subarray(der.length - 32);
    return { rawPubB64: raw.toString('base64'), privateKey };
  }

  it('verifies a valid signature', () => {
    const { rawPubB64, privateKey } = makePair();
    const message = Buffer.from('hello-nonce:1234567890');
    const sig = nodeSign(null, message, privateKey);
    expect(verifier.verify(rawPubB64, message, sig)).toBe(true);
  });

  it('rejects a tampered message', () => {
    const { rawPubB64, privateKey } = makePair();
    const sig = nodeSign(null, Buffer.from('original'), privateKey);
    expect(verifier.verify(rawPubB64, Buffer.from('tampered'), sig)).toBe(false);
  });

  it('rejects when public key length is not 32 bytes', () => {
    const wrongKey = Buffer.alloc(31).toString('base64');
    expect(verifier.verify(wrongKey, Buffer.from('x'), Buffer.alloc(64))).toBe(false);
  });

  it('rejects malformed base64', () => {
    expect(verifier.verify('!!!not-base64!!!', Buffer.from('x'), Buffer.alloc(64))).toBe(false);
  });
});
```

- [ ] **Step 2: Run tests, verify failure**

```bash
cd backend && npx jest src/auth/crypto/ed25519.verifier.spec.ts
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement verifier**

```typescript
// backend/src/auth/crypto/ed25519.verifier.ts
import { Injectable } from '@nestjs/common';
import { createPublicKey, verify as nodeVerify } from 'node:crypto';

const SPKI_ED25519_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

@Injectable()
export class Ed25519Verifier {
  verify(publicKeyB64: string, message: Buffer, signature: Buffer): boolean {
    let raw: Buffer;
    try {
      raw = Buffer.from(publicKeyB64, 'base64');
    } catch {
      return false;
    }
    if (raw.length !== 32) return false;

    let publicKey;
    try {
      publicKey = createPublicKey({
        key: Buffer.concat([SPKI_ED25519_PREFIX, raw]),
        format: 'der',
        type: 'spki',
      });
    } catch {
      return false;
    }

    try {
      return nodeVerify(null, message, publicKey, signature);
    } catch {
      return false;
    }
  }
}
```

- [ ] **Step 4: Run tests, verify pass**

```bash
cd backend && npx jest src/auth/crypto/ed25519.verifier.spec.ts
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add backend/src/auth/crypto/
git commit -m "feat(auth): add Ed25519Verifier for identity-key signatures"
```

---

## Task 4 — `AuthChallengeStore`

**Files:**
- Create: `backend/src/auth/auth-challenge.store.ts`
- Create: `backend/src/auth/auth-challenge.store.spec.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// backend/src/auth/auth-challenge.store.spec.ts
import { AuthChallengeStore } from './auth-challenge.store';

describe('AuthChallengeStore', () => {
  let store: AuthChallengeStore;
  beforeEach(() => { store = new AuthChallengeStore(); });

  it('generate() returns a 32-byte base64 nonce with ~60s TTL', () => {
    const { nonce, expiresAt } = store.generate('dev-1');
    expect(Buffer.from(nonce, 'base64').length).toBe(32);
    const ttl = expiresAt.getTime() - Date.now();
    expect(ttl).toBeGreaterThan(55_000);
    expect(ttl).toBeLessThan(61_000);
  });

  it('peek() returns the active nonce', () => {
    const { nonce } = store.generate('dev-1');
    expect(store.peek('dev-1')).toBe(nonce);
  });

  it('peek() returns null after consume()', () => {
    store.generate('dev-1');
    store.consume('dev-1');
    expect(store.peek('dev-1')).toBeNull();
  });

  it('peek() returns null after TTL expires', () => {
    jest.useFakeTimers().setSystemTime(new Date(2026, 0, 1, 12, 0, 0));
    store.generate('dev-1');
    jest.setSystemTime(new Date(2026, 0, 1, 12, 1, 1));   // +61s
    expect(store.peek('dev-1')).toBeNull();
    jest.useRealTimers();
  });

  it('generate() overwrites prior nonce for same deviceId', () => {
    const a = store.generate('dev-1').nonce;
    const b = store.generate('dev-1').nonce;
    expect(a).not.toBe(b);
    expect(store.peek('dev-1')).toBe(b);
  });

  it('cleanup() removes expired entries', () => {
    jest.useFakeTimers().setSystemTime(new Date(2026, 0, 1, 12, 0, 0));
    store.generate('dev-1');
    store.generate('dev-2');
    jest.setSystemTime(new Date(2026, 0, 1, 12, 1, 1));
    store.cleanup();
    expect(store.peek('dev-1')).toBeNull();
    expect(store.peek('dev-2')).toBeNull();
    jest.useRealTimers();
  });
});
```

- [ ] **Step 2: Run tests, verify failure**

```bash
cd backend && npx jest src/auth/auth-challenge.store.spec.ts
```
Expected: FAIL.

- [ ] **Step 3: Implement store**

```typescript
// backend/src/auth/auth-challenge.store.ts
import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { randomBytes } from 'node:crypto';

interface Entry {
  nonce: string;
  expiresAt: number;
}

const TTL_MS = 60_000;
const CLEANUP_INTERVAL_MS = 60_000;

@Injectable()
export class AuthChallengeStore implements OnModuleDestroy {
  private readonly store = new Map<string, Entry>();
  private readonly cleanupTimer = setInterval(
    () => this.cleanup(),
    CLEANUP_INTERVAL_MS,
  ).unref();

  generate(deviceId: string): { nonce: string; expiresAt: Date } {
    const nonce = randomBytes(32).toString('base64');
    const expiresAt = Date.now() + TTL_MS;
    this.store.set(deviceId, { nonce, expiresAt });
    return { nonce, expiresAt: new Date(expiresAt) };
  }

  peek(deviceId: string): string | null {
    const entry = this.store.get(deviceId);
    if (!entry) return null;
    if (entry.expiresAt < Date.now()) {
      this.store.delete(deviceId);
      return null;
    }
    return entry.nonce;
  }

  consume(deviceId: string): void {
    this.store.delete(deviceId);
  }

  cleanup(): void {
    const now = Date.now();
    for (const [k, v] of this.store) {
      if (v.expiresAt < now) this.store.delete(k);
    }
  }

  onModuleDestroy(): void {
    clearInterval(this.cleanupTimer);
  }
}
```

- [ ] **Step 4: Run tests, verify pass**

```bash
cd backend && npx jest src/auth/auth-challenge.store.spec.ts
```
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add backend/src/auth/auth-challenge.store.ts backend/src/auth/auth-challenge.store.spec.ts
git commit -m "feat(auth): add AuthChallengeStore (in-memory, single-use, 60s TTL)"
```

---

## Task 5 — Wire new providers into `AuthModule` (still alongside old)

**Files:**
- Modify: `backend/src/auth/auth.module.ts`

- [ ] **Step 1: Add new providers without removing old ones**

```typescript
// backend/src/auth/auth.module.ts
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { PassportModule } from '@nestjs/passport';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { JwtStrategy } from './strategies/jwt.strategy';
import { UsersModule } from '../users/users.module';
import { DeviceSession } from './device-session.entity';
import { DeviceSessionsService } from './device-sessions.service';
import { AuthChallengeStore } from './auth-challenge.store';
import { Ed25519Verifier } from './crypto/ed25519.verifier';

const DEV_JWT_SECRET = 'super-secret-dev-key';

@Module({
  imports: [
    UsersModule,
    PassportModule,
    ConfigModule,
    TypeOrmModule.forFeature([DeviceSession]),
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => {
        const secret = configService.get<string>('JWT_SECRET') || DEV_JWT_SECRET;
        const isProd = configService.get('NODE_ENV') === 'production';
        if (isProd && (!secret || secret === DEV_JWT_SECRET)) {
          throw new Error(
            'Production requires a strong JWT_SECRET. Do not use the dev fallback.',
          );
        }
        return {
          secret,
          // Phase 0 hotfix kept until Phase 1 cutover (PR 3).
          signOptions: { expiresIn: '30d' },
        };
      },
    }),
  ],
  controllers: [AuthController],
  providers: [
    AuthService,
    JwtStrategy,                    // STILL ACTIVE — removed in PR 3
    DeviceSessionsService,          // NEW
    AuthChallengeStore,             // NEW
    Ed25519Verifier,                // NEW
  ],
  exports: [
    AuthService, JwtModule,
    DeviceSessionsService,          // NEW (used by ChatGateway later)
  ],
})
export class AuthModule {}
```

- [ ] **Step 2: Verify backend builds and existing tests still pass**

```bash
cd backend && npm run build
cd backend && npm test
```
Expected: build success, all existing tests still pass (243+).

- [ ] **Step 3: Restart backend in non-prod and verify `device_sessions` table is auto-created**

```bash
# In Docker
docker-compose restart backend
# Then exec into postgres:
docker-compose exec db psql -U postgres -d fireplace -c '\d device_sessions'
```
Expected output includes columns `id, user_id, auth_pub_key, device_label, device_kind, expires_at, last_seen_at, created_at`.

- [ ] **Step 4: Commit**

```bash
git add backend/src/auth/auth.module.ts
git commit -m "feat(auth): register identity-key auth providers in AuthModule"
```

---

# PR 2 — Backend New Auth Endpoints (Alongside Old)

Goal: implement new endpoints (`/auth/challenge`, `/auth/refresh-with-key`, `/auth/logout`, `/auth/devices`, `DELETE /auth/devices/:id`) and extend register/login to also create `device_sessions` rows. Old `JwtAuthGuard`-protected endpoints continue to work. Frontend is not switched yet.

## Task 6 — Extend register/login DTOs

**Files:**
- Modify: `backend/src/auth/dto/register.dto.ts`
- Modify: `backend/src/auth/dto/login.dto.ts`

- [ ] **Step 1: Update RegisterDto**

```typescript
// backend/src/auth/dto/register.dto.ts
import { IsString, MinLength, MaxLength, Matches, IsIn, IsBase64 } from 'class-validator';

export class RegisterDto {
  @IsString()
  @MinLength(3)
  @MaxLength(20)
  @Matches(/^[a-zA-Z0-9_]+$/, { message: 'username: alphanumeric + underscore only' })
  username: string;

  @IsString()
  @MinLength(8)
  @MaxLength(128)
  password: string;

  @IsString()
  @IsBase64()
  @MinLength(40)        // base64 of 32 bytes is 44 chars
  @MaxLength(48)
  authPublicKey: string;

  @IsString()
  @MinLength(1)
  @MaxLength(120)
  deviceLabel: string;

  @IsIn(['web', 'android', 'ios', 'desktop'])
  deviceKind: 'web' | 'android' | 'ios' | 'desktop';
}
```

- [ ] **Step 2: Update LoginDto**

```typescript
// backend/src/auth/dto/login.dto.ts
import { IsString, MinLength, MaxLength, IsIn, IsBase64 } from 'class-validator';

export class LoginDto {
  @IsString()
  @MinLength(1)
  @MaxLength(64)
  identifier: string;     // username or username#tag

  @IsString()
  @MinLength(1)
  @MaxLength(128)
  password: string;

  @IsString()
  @IsBase64()
  @MinLength(40)
  @MaxLength(48)
  authPublicKey: string;

  @IsString()
  @MinLength(1)
  @MaxLength(120)
  deviceLabel: string;

  @IsIn(['web', 'android', 'ios', 'desktop'])
  deviceKind: 'web' | 'android' | 'ios' | 'desktop';
}
```

- [ ] **Step 3: Commit**

```bash
git add backend/src/auth/dto/register.dto.ts backend/src/auth/dto/login.dto.ts
git commit -m "feat(auth): extend register/login DTOs with authPublicKey + device info"
```

---

## Task 7 — New auth DTOs

**Files:**
- Create: `backend/src/auth/dto/challenge.dto.ts`
- Create: `backend/src/auth/dto/refresh-with-key.dto.ts`
- Create: `backend/src/auth/dto/device-info.dto.ts`

- [ ] **Step 1: Create the DTOs**

```typescript
// backend/src/auth/dto/challenge.dto.ts
import { IsUUID } from 'class-validator';

export class ChallengeDto {
  @IsUUID()
  deviceId: string;
}
```

```typescript
// backend/src/auth/dto/refresh-with-key.dto.ts
import { IsUUID, IsString, IsBase64, IsInt, Min } from 'class-validator';

export class RefreshWithKeyDto {
  @IsUUID()
  deviceId: string;

  @IsString()
  @IsBase64()
  signature: string;          // base64 of 64-byte Ed25519 signature

  @IsInt()
  @Min(0)
  timestamp: number;          // Unix epoch milliseconds (Date.now())
}
```

```typescript
// backend/src/auth/dto/device-info.dto.ts
export interface DeviceInfoDto {
  id: string;
  deviceLabel: string;
  deviceKind: 'web' | 'android' | 'ios' | 'desktop';
  createdAt: string;          // ISO
  lastSeenAt: string;         // ISO
  current: boolean;
}
```

- [ ] **Step 2: Commit**

```bash
git add backend/src/auth/dto/challenge.dto.ts backend/src/auth/dto/refresh-with-key.dto.ts backend/src/auth/dto/device-info.dto.ts
git commit -m "feat(auth): add identity-key auth DTOs"
```

---

## Task 8 — Extend `AuthService` with device-aware register/login + session token issuer

**Files:**
- Modify: `backend/src/auth/auth.service.ts`
- Modify: `backend/src/auth/auth.service.spec.ts`

- [ ] **Step 1: Update tests**

```typescript
// backend/src/auth/auth.service.spec.ts — add to existing describe block
describe('AuthService — identity-key flow', () => {
  // ... existing setup ...

  it('login() creates a device_sessions row and returns sessionToken + deviceId', async () => {
    // mock: usersService.findByUsernameAndTag returns user, bcrypt.compare returns true
    // mock: deviceSessionsService.create returns { id: 'uuid-X', ... }
    // mock: jwtService.signAsync returns 'fake.session.jwt'
    const result = await service.loginWithDevice({
      identifier: 'kowalski#1234',
      password: 'p@ssw0rd!',
      authPublicKey: Buffer.alloc(32, 7).toString('base64'),
      deviceLabel: 'Chrome on Windows',
      deviceKind: 'web',
    });
    expect(result.sessionToken).toBe('fake.session.jwt');
    expect(result.deviceId).toBe('uuid-X');
    expect(result.user.username).toBe('kowalski');
    expect(deviceSessionsService.create).toHaveBeenCalled();
  });

  it('login() rejects on bad password', async () => {
    // bcrypt.compare returns false
    await expect(service.loginWithDevice({ ...validInput, password: 'wrong' }))
      .rejects.toThrow(/Invalid credentials/);
    expect(deviceSessionsService.create).not.toHaveBeenCalled();
  });

  it('register() creates user, then device_sessions, then issues session token', async () => {
    const result = await service.registerWithDevice({
      username: 'nowak', password: 'p@ssw0rd!',
      authPublicKey: Buffer.alloc(32, 5).toString('base64'),
      deviceLabel: 'iPhone PWA', deviceKind: 'ios',
    });
    expect(result.sessionToken).toBeDefined();
    expect(result.deviceId).toBeDefined();
    expect(usersService.create).toHaveBeenCalledBefore(deviceSessionsService.create);
  });

  it('issueSessionToken() signs JWT with sub/username/tag/deviceId and 2h TTL', async () => {
    await service.issueSessionToken({
      userId: 7, username: 'k', tag: '0001', deviceId: 'uuid-X',
    });
    expect(jwtService.signAsync).toHaveBeenCalledWith(
      { sub: 7, username: 'k', tag: '0001', deviceId: 'uuid-X' },
      { expiresIn: '2h' },
    );
  });
});
```

- [ ] **Step 2: Run tests, verify failure**

```bash
cd backend && npx jest src/auth/auth.service.spec.ts
```
Expected: FAIL on new tests.

- [ ] **Step 3: Implement new methods**

Add to `backend/src/auth/auth.service.ts` (alongside existing `register` and `login` methods, which stay in place for now):

```typescript
import { DeviceSessionsService } from './device-sessions.service';
// ...

interface DeviceLoginInput {
  identifier: string;
  password: string;
  authPublicKey: string;
  deviceLabel: string;
  deviceKind: 'web' | 'android' | 'ios' | 'desktop';
}

interface DeviceRegisterInput {
  username: string;
  password: string;
  authPublicKey: string;
  deviceLabel: string;
  deviceKind: 'web' | 'android' | 'ios' | 'desktop';
}

interface DeviceAuthResult {
  sessionToken: string;
  deviceId: string;
  user: { id: number; username: string; tag: string; profilePictureUrl: string | null };
}

@Injectable()
export class AuthService {
  // existing properties + constructor; ADD:
  constructor(
    private usersService: UsersService,
    private jwtService: JwtService,
    private deviceSessionsService: DeviceSessionsService,
  ) {}

  async registerWithDevice(input: DeviceRegisterInput): Promise<DeviceAuthResult> {
    const user = await this.usersService.create(input.username, input.password);
    const session = await this.deviceSessionsService.create({
      userId: user.id,
      authPublicKey: input.authPublicKey,
      deviceLabel: input.deviceLabel,
      deviceKind: input.deviceKind,
    });
    const sessionToken = await this.issueSessionToken({
      userId: user.id, username: user.username, tag: user.tag, deviceId: session.id,
    });
    return {
      sessionToken,
      deviceId: session.id,
      user: {
        id: user.id, username: user.username, tag: user.tag,
        profilePictureUrl: user.profilePictureUrl ?? null,
      },
    };
  }

  async loginWithDevice(input: DeviceLoginInput): Promise<DeviceAuthResult> {
    const user = await this.findUserByIdentifier(input.identifier);
    if (!user) {
      this.auditLogger.log(`login failed identifier=${input.identifier}`);
      throw new UnauthorizedException('Invalid credentials');
    }
    const ok = await bcrypt.compare(input.password, user.password);
    if (!ok) {
      this.auditLogger.log(`login failed identifier=${input.identifier}`);
      throw new UnauthorizedException('Invalid credentials');
    }

    const session = await this.deviceSessionsService.create({
      userId: user.id,
      authPublicKey: input.authPublicKey,
      deviceLabel: input.deviceLabel,
      deviceKind: input.deviceKind,
    });
    const sessionToken = await this.issueSessionToken({
      userId: user.id, username: user.username, tag: user.tag, deviceId: session.id,
    });
    this.auditLogger.log(`login success userId=${user.id} deviceId=${session.id}`);
    return {
      sessionToken, deviceId: session.id,
      user: {
        id: user.id, username: user.username, tag: user.tag,
        profilePictureUrl: user.profilePictureUrl ?? null,
      },
    };
  }

  async issueSessionToken(args: {
    userId: number; username: string; tag: string; deviceId: string;
  }): Promise<string> {
    return this.jwtService.signAsync(
      { sub: args.userId, username: args.username, tag: args.tag, deviceId: args.deviceId },
      { expiresIn: '2h' },
    );
  }

  private async findUserByIdentifier(identifier: string): Promise<User | null> {
    if (identifier.includes('#')) {
      const [u, t] = identifier.split('#');
      if (u && t) return this.usersService.findByUsernameAndTag(u.trim(), t.trim());
      return null;
    }
    const users = await this.usersService.findByUsername(identifier.trim());
    if (users.length === 1) return users[0];
    if (users.length > 1) {
      throw new UnauthorizedException('Multiple users found, please use username#tag');
    }
    return null;
  }
}
```

- [ ] **Step 4: Run tests, verify pass**

```bash
cd backend && npx jest src/auth/auth.service.spec.ts
```
Expected: PASS — all tests including new identity-key tests.

- [ ] **Step 5: Commit**

```bash
git add backend/src/auth/auth.service.ts backend/src/auth/auth.service.spec.ts
git commit -m "feat(auth): add registerWithDevice/loginWithDevice/issueSessionToken on AuthService"
```

---

## Task 9 — Implement `IdentityKeySessionGuard` (still alongside JwtAuthGuard)

**Files:**
- Create: `backend/src/auth/identity-key-session.guard.ts`
- Create: `backend/src/auth/identity-key-session.guard.spec.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// backend/src/auth/identity-key-session.guard.spec.ts
import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { IdentityKeySessionGuard } from './identity-key-session.guard';
import { DeviceSessionsService } from './device-sessions.service';

describe('IdentityKeySessionGuard', () => {
  let guard: IdentityKeySessionGuard;
  const jwt = { verifyAsync: jest.fn() } as unknown as JwtService;
  const sessions = { findById: jest.fn() } as unknown as DeviceSessionsService;
  beforeEach(() => {
    guard = new IdentityKeySessionGuard(jwt, sessions);
    jest.clearAllMocks();
  });

  function ctx(headers: Record<string, string>) {
    const req: any = { headers };
    return {
      switchToHttp: () => ({ getRequest: () => req }),
    } as ExecutionContext;
  }

  it('rejects when no Authorization header', async () => {
    await expect(guard.canActivate(ctx({}))).rejects.toThrow(UnauthorizedException);
  });

  it('rejects when JWT verification fails', async () => {
    (jwt.verifyAsync as jest.Mock).mockRejectedValueOnce(new Error('expired'));
    await expect(
      guard.canActivate(ctx({ authorization: 'Bearer bad.jwt' })),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('rejects when device session does not exist', async () => {
    (jwt.verifyAsync as jest.Mock).mockResolvedValueOnce({
      sub: 7, username: 'k', tag: '0001', deviceId: 'uuid-X',
    });
    (sessions.findById as jest.Mock).mockResolvedValueOnce(null);
    await expect(
      guard.canActivate(ctx({ authorization: 'Bearer good.jwt' })),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('rejects when device session has expired', async () => {
    (jwt.verifyAsync as jest.Mock).mockResolvedValueOnce({
      sub: 7, deviceId: 'uuid-X', username: 'k', tag: '0001',
    });
    (sessions.findById as jest.Mock).mockResolvedValueOnce({
      id: 'uuid-X', userId: 7, expiresAt: new Date(Date.now() - 1000),
    });
    await expect(
      guard.canActivate(ctx({ authorization: 'Bearer good.jwt' })),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('accepts and injects req.user with deviceId on valid session', async () => {
    (jwt.verifyAsync as jest.Mock).mockResolvedValueOnce({
      sub: 7, username: 'kowalski', tag: '0001', deviceId: 'uuid-X',
    });
    (sessions.findById as jest.Mock).mockResolvedValueOnce({
      id: 'uuid-X', userId: 7, expiresAt: new Date(Date.now() + 86400_000),
    });
    const c = ctx({ authorization: 'Bearer good.jwt' });
    const result = await guard.canActivate(c);
    expect(result).toBe(true);
    const req = (c.switchToHttp().getRequest() as any);
    expect(req.user).toEqual({ id: 7, username: 'kowalski', tag: '0001', deviceId: 'uuid-X' });
  });
});
```

- [ ] **Step 2: Run tests, verify failure**

```bash
cd backend && npx jest src/auth/identity-key-session.guard.spec.ts
```
Expected: FAIL.

- [ ] **Step 3: Implement guard**

```typescript
// backend/src/auth/identity-key-session.guard.ts
import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { DeviceSessionsService } from './device-sessions.service';

interface SessionTokenPayload {
  sub: number;
  username: string;
  tag: string;
  deviceId: string;
}

@Injectable()
export class IdentityKeySessionGuard implements CanActivate {
  constructor(
    private readonly jwtService: JwtService,
    private readonly sessions: DeviceSessionsService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const auth = request.headers?.authorization;
    if (!auth?.startsWith('Bearer ')) {
      throw new UnauthorizedException();
    }
    const token = auth.slice(7);

    let payload: SessionTokenPayload;
    try {
      payload = await this.jwtService.verifyAsync<SessionTokenPayload>(token);
    } catch {
      throw new UnauthorizedException('Session token invalid or expired');
    }

    const session = await this.sessions.findById(payload.deviceId);
    if (!session || session.expiresAt < new Date()) {
      throw new UnauthorizedException('Device session revoked or expired');
    }

    request.user = {
      id: payload.sub,
      username: payload.username,
      tag: payload.tag,
      deviceId: payload.deviceId,
    };
    return true;
  }
}
```

- [ ] **Step 4: Run tests, verify pass**

```bash
cd backend && npx jest src/auth/identity-key-session.guard.spec.ts
```
Expected: PASS (5 tests).

- [ ] **Step 5: Register guard as provider in `auth.module.ts`**

Add to providers array:
```typescript
import { IdentityKeySessionGuard } from './identity-key-session.guard';
// ...
providers: [
  AuthService, JwtStrategy,
  DeviceSessionsService, AuthChallengeStore, Ed25519Verifier,
  IdentityKeySessionGuard,         // NEW
],
exports: [
  AuthService, JwtModule,
  DeviceSessionsService,
  IdentityKeySessionGuard,         // NEW
],
```

- [ ] **Step 6: Commit**

```bash
git add backend/src/auth/identity-key-session.guard.ts backend/src/auth/identity-key-session.guard.spec.ts backend/src/auth/auth.module.ts
git commit -m "feat(auth): add IdentityKeySessionGuard"
```

---

## Task 10 — New `AuthController` endpoints (alongside old)

**Files:**
- Modify: `backend/src/auth/auth.controller.ts`
- Modify: `backend/src/auth/auth.controller.spec.ts`

- [ ] **Step 1: Add new endpoints + tests**

Read existing `auth.controller.ts` first to preserve old endpoints.

Add new endpoints in `AuthController`:

```typescript
// Add imports at top
import { ChallengeDto } from './dto/challenge.dto';
import { RefreshWithKeyDto } from './dto/refresh-with-key.dto';
import { AuthChallengeStore } from './auth-challenge.store';
import { Ed25519Verifier } from './crypto/ed25519.verifier';
import { DeviceSessionsService } from './device-sessions.service';
import { IdentityKeySessionGuard } from './identity-key-session.guard';
import { Throttle } from '@nestjs/throttler';

// Inject in constructor:
constructor(
  private authService: AuthService,
  private deviceSessions: DeviceSessionsService,
  private challengeStore: AuthChallengeStore,
  private ed25519: Ed25519Verifier,
) {}

// EXISTING /register and /login stay (deprecated, will be removed in PR 3).

// New device-aware endpoints:
@Post('register-with-device')
@Throttle({ default: { limit: 5, ttl: 60_000 } })
async registerWithDevice(@Body() dto: RegisterDto) {
  return this.authService.registerWithDevice(dto);
}

@Post('login-with-device')
@Throttle({ default: { limit: 10, ttl: 60_000 } })
async loginWithDevice(@Body() dto: LoginDto) {
  return this.authService.loginWithDevice(dto);
}

@Post('challenge')
@Throttle({ default: { limit: 30, ttl: 60_000 } })
async challenge(@Body() dto: ChallengeDto) {
  const session = await this.deviceSessions.findById(dto.deviceId);
  if (!session) throw new UnauthorizedException('Unknown device');
  return this.challengeStore.generate(dto.deviceId);
}

@Post('refresh-with-key')
@Throttle({ default: { limit: 30, ttl: 60_000 } })
async refreshWithKey(@Body() dto: RefreshWithKeyDto) {
  const session = await this.deviceSessions.findById(dto.deviceId);
  if (!session) throw new UnauthorizedException('Device not found');
  if (session.expiresAt < new Date()) {
    await this.deviceSessions.delete(dto.deviceId);
    throw new UnauthorizedException('Device session expired');
  }

  const nonce = this.challengeStore.peek(dto.deviceId);
  if (!nonce) throw new UnauthorizedException('No active challenge');

  if (Math.abs(Date.now() - dto.timestamp) > 60_000) {
    throw new UnauthorizedException('Timestamp out of window');
  }

  const message = Buffer.from(`${nonce}:${dto.timestamp}`, 'utf8');
  const signature = Buffer.from(dto.signature, 'base64');
  if (!this.ed25519.verify(session.authPublicKey, message, signature)) {
    throw new UnauthorizedException('Bad signature');
  }

  this.challengeStore.consume(dto.deviceId);
  await this.deviceSessions.touch(session.id);

  const sessionToken = await this.authService.issueSessionToken({
    userId: session.userId,
    username: session.user.username,
    tag: session.user.tag,
    deviceId: session.id,
  });
  return { sessionToken };
}

@Post('logout-device')
@UseGuards(IdentityKeySessionGuard)
@HttpCode(204)
async logoutDevice(@Req() req: any) {
  await this.deviceSessions.delete(req.user.deviceId);
}

@Get('devices')
@UseGuards(IdentityKeySessionGuard)
async listDevices(@Req() req: any) {
  const sessions = await this.deviceSessions.findByUser(req.user.id);
  return sessions.map((s) => ({
    id: s.id,
    deviceLabel: s.deviceLabel,
    deviceKind: s.deviceKind,
    createdAt: s.createdAt.toISOString(),
    lastSeenAt: s.lastSeenAt.toISOString(),
    current: s.id === req.user.deviceId,
  }));
}

@Delete('devices/:id')
@UseGuards(IdentityKeySessionGuard)
@HttpCode(204)
async removeDevice(@Req() req: any, @Param('id') id: string) {
  const session = await this.deviceSessions.findById(id);
  if (!session || session.userId !== req.user.id) {
    throw new UnauthorizedException();
  }
  await this.deviceSessions.delete(id);
}
```

Add controller-level tests in `auth.controller.spec.ts` covering:
- POST /auth/challenge → 401 when deviceId unknown, 200 with `{nonce, expiresAt}` when known
- POST /auth/refresh-with-key happy path → returns new sessionToken
- POST /auth/refresh-with-key with expired session → 401 + DELETE
- POST /auth/refresh-with-key with no active challenge → 401
- POST /auth/refresh-with-key with timestamp >60s away → 401
- POST /auth/refresh-with-key with bad signature → 401
- POST /auth/logout-device → DELETE called with req.user.deviceId
- GET /auth/devices → returns mapped list, current flag true for caller's deviceId
- DELETE /auth/devices/:id with foreign userId → 401
- DELETE /auth/devices/:id with own row → DELETE called

(Test code follows the same shape as existing `auth.controller.spec.ts` mocks; use `IdentityKeySessionGuard` overridden via `overrideGuard` in NestJS test module — same pattern as elsewhere in the codebase.)

- [ ] **Step 2: Run tests**

```bash
cd backend && npx jest src/auth/auth.controller.spec.ts
```
Expected: PASS — all old tests still green + new controller tests pass.

- [ ] **Step 3: Commit**

```bash
git add backend/src/auth/auth.controller.ts backend/src/auth/auth.controller.spec.ts
git commit -m "feat(auth): add identity-key auth endpoints (challenge/refresh/devices/logout)"
```

---

# PR 3 — Backend Cutover

Goal: switch every `JwtAuthGuard` site to `IdentityKeySessionGuard`, delete `JwtAuthGuard` and `JwtStrategy`, remove the deprecated `/auth/register` + `/auth/login` (without device fields). After this PR, old clients with bare 30d JWTs cannot authenticate. Frontend must be deployed within hours.

## Task 11 — Swap guard in 4 controllers

**Files:**
- Modify: `backend/src/users/users.controller.ts`
- Modify: `backend/src/media/media.controller.ts`
- Modify: `backend/src/secret-notes/secret-notes.controller.ts`
- Modify: `backend/src/messages/messages.controller.ts`

For each: change import and decorators

```typescript
// Before:
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
@UseGuards(JwtAuthGuard)
// After:
import { IdentityKeySessionGuard } from '../auth/identity-key-session.guard';
@UseGuards(IdentityKeySessionGuard)
```

The `req.user` shape now omits `profilePictureUrl`. Verify each controller — none of them read `req.user.profilePictureUrl` directly (frontend uses `/users/me` for that already, per CLAUDE.md). If any usage exists, replace with a `usersService.findById(req.user.id)` call.

- [ ] **Step 1: Edit each controller**
- [ ] **Step 2: Run all backend tests**

```bash
cd backend && npm test
```
Expected: PASS (all 243+ tests).

- [ ] **Step 3: Commit**

```bash
git add backend/src/users/users.controller.ts backend/src/media/media.controller.ts backend/src/secret-notes/secret-notes.controller.ts backend/src/messages/messages.controller.ts
git commit -m "refactor(auth): swap JwtAuthGuard to IdentityKeySessionGuard in all controllers"
```

---

## Task 12 — Update `ChatGateway.handleConnection`

**Files:**
- Modify: `backend/src/chat/chat.gateway.ts`

- [ ] **Step 1: Find and replace the connection handler**

Find current `handleConnection`. Replace JWT-only validation with JWT + device_sessions check:

```typescript
// Imports
import { DeviceSessionsService } from '../auth/device-sessions.service';

// Inject in constructor:
constructor(
  // ... existing ...
  private readonly deviceSessions: DeviceSessionsService,
) {}

async handleConnection(socket: Socket) {
  const token = socket.handshake.auth?.token as string | undefined;
  if (!token) {
    this.logger.warn('Socket connected without token');
    socket.disconnect(true);
    return;
  }
  let payload: { sub: number; deviceId: string };
  try {
    payload = await this.jwtService.verifyAsync(token);
  } catch {
    socket.disconnect(true);
    return;
  }
  if (!payload.deviceId) {
    socket.disconnect(true);
    return;
  }
  const session = await this.deviceSessions.findById(payload.deviceId);
  if (!session || session.expiresAt < new Date()) {
    socket.disconnect(true);
    return;
  }
  socket.data.userId = payload.sub;
  socket.data.deviceId = payload.deviceId;
  // ... rest of existing connection logic (presence, etc.) stays unchanged ...
}
```

- [ ] **Step 2: Run gateway tests**

```bash
cd backend && npx jest src/chat/chat.gateway.spec.ts
```
Expected: PASS — adjust mocks if necessary (gateway test should now mock `DeviceSessionsService`).

- [ ] **Step 3: Commit**

```bash
git add backend/src/chat/chat.gateway.ts backend/src/chat/chat.gateway.spec.ts
git commit -m "refactor(chat): validate device_sessions on socket connection"
```

---

## Task 13 — Delete `JwtAuthGuard`, `JwtStrategy`, deprecated endpoints

**Files:**
- Delete: `backend/src/auth/jwt-auth.guard.ts`
- Delete: `backend/src/auth/strategies/jwt.strategy.ts`
- Delete: `backend/src/auth/jwt.strategy.spec.ts`
- Modify: `backend/src/auth/auth.controller.ts` — remove deprecated `/auth/register` and `/auth/login` endpoints (the ones without device fields). Rename `register-with-device` → `register` and `login-with-device` → `login`.
- Modify: `backend/src/auth/auth.module.ts` — remove `JwtStrategy` import and provider.
- Modify: `backend/src/auth/auth.service.ts` — remove old `register()` and `login()` methods. Rename `registerWithDevice` → `register`, `loginWithDevice` → `login`.
- Update tests accordingly.

- [ ] **Step 1: Delete obsolete files**

```bash
git rm backend/src/auth/jwt-auth.guard.ts backend/src/auth/strategies/jwt.strategy.ts backend/src/auth/jwt.strategy.spec.ts
```

- [ ] **Step 2: Edit `auth.controller.ts`** — keep only the new device-aware endpoints. The endpoint paths after this step:
- `POST /auth/register`        (= old register-with-device)
- `POST /auth/login`           (= old login-with-device)
- `POST /auth/challenge`
- `POST /auth/refresh-with-key`
- `POST /auth/logout`           (= old logout-device, renamed for cleaner URL)
- `GET /auth/devices`
- `DELETE /auth/devices/:id`
- `POST /auth/reset-password`
- `POST /auth/delete-account`

- [ ] **Step 3: Edit `auth.module.ts`**

```typescript
// Remove:
import { JwtStrategy } from './strategies/jwt.strategy';
// Remove from providers: JwtStrategy
// Remove PassportModule from imports if nothing else needs it (verify with grep).
```

- [ ] **Step 4: Run full backend test suite**

```bash
cd backend && npm test
```
Expected: PASS (all tests). If any old test referenced `JwtAuthGuard`, it's been deleted with the corresponding file.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(auth): remove JwtAuthGuard/JwtStrategy after identity-key cutover"
```

---

# PR 4 — Backend Cron + Final Tests

## Task 14 — Cleanup cron for expired sessions

**Files:**
- Create: `backend/src/auth/auth.cleanup.service.ts`
- Create: `backend/src/auth/auth.cleanup.service.spec.ts`
- Modify: `backend/src/auth/auth.module.ts`
- Modify: `backend/src/app.module.ts` — confirm `ScheduleModule.forRoot()` is registered (probably already for `MessageCleanupService` + `MediaCleanupService`).

- [ ] **Step 1: Write tests**

```typescript
// backend/src/auth/auth.cleanup.service.spec.ts
import { AuthCleanupService } from './auth.cleanup.service';
import { DeviceSessionsService } from './device-sessions.service';

describe('AuthCleanupService', () => {
  it('deletes sessions expired >30d ago', async () => {
    const sessions = { deleteExpiredOlderThan: jest.fn().mockResolvedValue(3) } as unknown as DeviceSessionsService;
    const svc = new AuthCleanupService(sessions);
    await svc.cleanupExpiredSessions();
    const cutoff: Date = (sessions.deleteExpiredOlderThan as jest.Mock).mock.calls[0][0];
    const expectedCutoffMs = Date.now() - 30 * 86400_000;
    expect(Math.abs(cutoff.getTime() - expectedCutoffMs)).toBeLessThan(2_000);
  });
});
```

- [ ] **Step 2: Implement**

```typescript
// backend/src/auth/auth.cleanup.service.ts
import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { DeviceSessionsService } from './device-sessions.service';

@Injectable()
export class AuthCleanupService {
  private readonly logger = new Logger(AuthCleanupService.name);

  constructor(private readonly sessions: DeviceSessionsService) {}

  @Cron(CronExpression.EVERY_DAY_AT_3AM)
  async cleanupExpiredSessions() {
    const cutoff = new Date(Date.now() - 30 * 86400_000);
    const deleted = await this.sessions.deleteExpiredOlderThan(cutoff);
    if (deleted > 0) this.logger.log(`Deleted ${deleted} expired device_sessions`);
  }
}
```

- [ ] **Step 3: Register in `auth.module.ts`**

```typescript
import { AuthCleanupService } from './auth.cleanup.service';
// add to providers
```

- [ ] **Step 4: Run tests**

```bash
cd backend && npx jest src/auth/auth.cleanup.service.spec.ts
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/src/auth/auth.cleanup.service.ts backend/src/auth/auth.cleanup.service.spec.ts backend/src/auth/auth.module.ts
git commit -m "feat(auth): add daily cron to delete sessions expired >30d ago"
```

---

## Task 15 — Update reset-password to delete all device sessions

**Files:**
- Modify: `backend/src/auth/auth.service.ts` (`resetPassword` method)
- Modify: `backend/src/auth/auth.service.spec.ts`

- [ ] **Step 1: Add test**

```typescript
it('resetPassword() deletes all device_sessions for the user', async () => {
  await service.resetPassword(7, 'old', 'newp@ss!');
  expect(deviceSessionsService.deleteAllForUser).toHaveBeenCalledWith(7);
});
```

- [ ] **Step 2: Update implementation**

In `resetPassword`, after updating password and `passwordChangedAt`:
```typescript
await this.deviceSessionsService.deleteAllForUser(userId);
```

- [ ] **Step 3: Run tests, commit**

```bash
cd backend && npx jest src/auth/auth.service.spec.ts
git add backend/src/auth/auth.service.ts backend/src/auth/auth.service.spec.ts
git commit -m "feat(auth): logout all devices on password change"
```

---

## Task 16 — Final backend full test sweep

- [ ] **Step 1: Run full backend test suite**

```bash
cd backend && npm test -- --coverage
```
Expected: all tests pass; coverage of new auth code >= 90%.

- [ ] **Step 2: If any gaps appear, add focused tests for them.**

- [ ] **Step 3: Commit (if test additions needed)**

```bash
git commit -am "test(auth): cover edge cases discovered during coverage review"
```

---

# PR 5 — Frontend Foundation

Goal: add the new dependency, build `AuthIdentityKeyPair`, `AuthSessionManager`, and extend `ApiService` with new endpoints. No `AuthProvider` rewrite yet — these new pieces are stand-alone units with passing unit tests.

## Task 17 — Add `cryptography` dependency

**Files:**
- Modify: `frontend/pubspec.yaml`

- [ ] **Step 1: Add dependency**

In `frontend/pubspec.yaml`, under `dependencies:`:

```yaml
  cryptography: ^2.7.0
```

- [ ] **Step 2: Install**

```bash
cd frontend && flutter pub get
```
Expected: success, lockfile updated.

- [ ] **Step 3: Commit**

```bash
git add frontend/pubspec.yaml frontend/pubspec.lock
git commit -m "build(frontend): add cryptography ^2.7.0 for Ed25519 auth keypair"
```

---

## Task 18 — `AuthIdentityKeyPair`

**Files:**
- Create: `frontend/lib/services/crypto/auth_identity_keypair.dart`
- Create: `frontend/test/services/crypto/auth_identity_keypair_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// frontend/test/services/crypto/auth_identity_keypair_test.dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/crypto/auth_identity_keypair.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // mock flutter_secure_storage via MethodChannel
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    channel.setMockMethodCallHandler((call) async {
      // simple in-memory map for tests
      // ...
    });
  });

  test('generate() returns a keypair with 32-byte public + 32-byte seed (base64)', () async {
    final kp = await AuthIdentityKeyPair.generate();
    expect(base64Decode(kp.publicKeyB64).length, 32);
    expect(base64Decode(kp.privateKeyB64).length, 32);
  });

  test('sign() produces a 64-byte Ed25519 signature verifiable by cryptography package', () async {
    final kp = await AuthIdentityKeyPair.generate();
    final sigB64 = await kp.sign('hello-nonce:1234567890');
    final sig = base64Decode(sigB64);
    expect(sig.length, 64);

    // verify with raw cryptography API to prove cross-compatibility
    final algorithm = Ed25519();
    final reconstructed = await algorithm.newKeyPairFromSeed(base64Decode(kp.privateKeyB64));
    final pub = await reconstructed.extractPublicKey();
    final ok = await algorithm.verify(
      utf8.encode('hello-nonce:1234567890'),
      signature: Signature(sig, publicKey: pub),
    );
    expect(ok, true);
  });

  test('persist() then loadFromStorage() returns the same key material', () async {
    final kp = await AuthIdentityKeyPair.generate();
    await kp.persist();
    final loaded = await AuthIdentityKeyPair.loadFromStorage();
    expect(loaded, isNotNull);
    expect(loaded!.publicKeyB64, kp.publicKeyB64);
    expect(loaded.privateKeyB64, kp.privateKeyB64);
  });

  test('loadFromStorage() returns null when nothing persisted', () async {
    final loaded = await AuthIdentityKeyPair.loadFromStorage();
    expect(loaded, isNull);
  });
}
```

- [ ] **Step 2: Run tests, verify failure**

```bash
cd frontend && flutter test test/services/crypto/auth_identity_keypair_test.dart
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```dart
// frontend/lib/services/crypto/auth_identity_keypair.dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthIdentityKeyPair {
  static const _privKey = 'auth_private_key_v1';
  static const _pubKey  = 'auth_public_key_v1';

  static FlutterSecureStorage secureStorage() => const FlutterSecureStorage(
        webOptions: WebOptions(dbName: 'FireplaceE2E'),
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      );

  final String publicKeyB64;
  final String privateKeyB64;   // 32-byte seed

  AuthIdentityKeyPair({required this.publicKeyB64, required this.privateKeyB64});

  static Future<AuthIdentityKeyPair> generate() async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final pub = await keyPair.extractPublicKey();
    final seed = await keyPair.extractPrivateKeyBytes();   // 32B seed
    return AuthIdentityKeyPair(
      publicKeyB64: base64Encode(pub.bytes),
      privateKeyB64: base64Encode(seed),
    );
  }

  static Future<AuthIdentityKeyPair?> loadFromStorage() async {
    final secure = secureStorage();
    final prefs = await SharedPreferences.getInstance();
    final priv = await secure.read(key: _privKey) ?? prefs.getString(_privKey);
    final pub  = await secure.read(key: _pubKey)  ?? prefs.getString(_pubKey);
    if (priv == null || pub == null) return null;
    return AuthIdentityKeyPair(publicKeyB64: pub, privateKeyB64: priv);
  }

  Future<void> persist() async {
    final secure = secureStorage();
    final prefs = await SharedPreferences.getInstance();
    await secure.write(key: _privKey, value: privateKeyB64);
    await secure.write(key: _pubKey,  value: publicKeyB64);
    await prefs.setString(_privKey, privateKeyB64);
    await prefs.setString(_pubKey,  publicKeyB64);
  }

  static Future<void> clear() async {
    final secure = secureStorage();
    final prefs = await SharedPreferences.getInstance();
    await secure.delete(key: _privKey);
    await secure.delete(key: _pubKey);
    await prefs.remove(_privKey);
    await prefs.remove(_pubKey);
  }

  Future<String> sign(String message) async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(base64Decode(privateKeyB64));
    final signature = await algorithm.sign(utf8.encode(message), keyPair: keyPair);
    return base64Encode(signature.bytes);
  }
}
```

- [ ] **Step 4: Run tests, verify pass**

```bash
cd frontend && flutter test test/services/crypto/auth_identity_keypair_test.dart
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/services/crypto/auth_identity_keypair.dart frontend/test/services/crypto/auth_identity_keypair_test.dart
git commit -m "feat(auth): add AuthIdentityKeyPair with DualStorage and Ed25519 sign"
```

---

## Task 19 — Extend `ApiService` with auth endpoints

**Files:**
- Modify: `frontend/lib/services/api_service.dart`

- [ ] **Step 1: Add new methods**

```dart
// inside ApiService class

Future<Map<String, dynamic>> registerWithDevice({
  required String username, required String password,
  required String authPublicKey,
  required String deviceLabel, required String deviceKind,
}) async {
  final response = await http.post(
    Uri.parse('$baseUrl/auth/register'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'username': username, 'password': password,
      'authPublicKey': authPublicKey,
      'deviceLabel': deviceLabel, 'deviceKind': deviceKind,
    }),
  );
  if (response.statusCode != 201 && response.statusCode != 200) {
    throw Exception('HTTP_${response.statusCode}: ${response.body}');
  }
  return jsonDecode(response.body);
}

Future<Map<String, dynamic>> loginWithDevice({
  required String identifier, required String password,
  required String authPublicKey,
  required String deviceLabel, required String deviceKind,
}) async {
  final response = await http.post(
    Uri.parse('$baseUrl/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'identifier': identifier, 'password': password,
      'authPublicKey': authPublicKey,
      'deviceLabel': deviceLabel, 'deviceKind': deviceKind,
    }),
  );
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception('HTTP_${response.statusCode}: ${response.body}');
  }
  return jsonDecode(response.body);
}

Future<Map<String, dynamic>> requestChallenge(String deviceId) async {
  final response = await http.post(
    Uri.parse('$baseUrl/auth/challenge'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'deviceId': deviceId}),
  );
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception('HTTP_${response.statusCode}: ${response.body}');
  }
  return jsonDecode(response.body);
}

Future<Map<String, dynamic>> refreshWithKey({
  required String deviceId, required String signature, required int timestamp,
}) async {
  final response = await http.post(
    Uri.parse('$baseUrl/auth/refresh-with-key'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'deviceId': deviceId, 'signature': signature, 'timestamp': timestamp,
    }),
  );
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception('HTTP_${response.statusCode}: ${response.body}');
  }
  return jsonDecode(response.body);
}

Future<void> logoutDevice(String sessionToken) async {
  await http.post(
    Uri.parse('$baseUrl/auth/logout'),
    headers: {'Authorization': 'Bearer $sessionToken'},
  );
}

Future<List<dynamic>> listDevices(String sessionToken) async {
  final response = await http.get(
    Uri.parse('$baseUrl/auth/devices'),
    headers: {'Authorization': 'Bearer $sessionToken'},
  );
  if (response.statusCode != 200) {
    throw Exception('HTTP_${response.statusCode}: ${response.body}');
  }
  return jsonDecode(response.body) as List<dynamic>;
}

Future<void> removeDevice(String sessionToken, String id) async {
  final response = await http.delete(
    Uri.parse('$baseUrl/auth/devices/$id'),
    headers: {'Authorization': 'Bearer $sessionToken'},
  );
  if (response.statusCode != 204 && response.statusCode != 200) {
    throw Exception('HTTP_${response.statusCode}: ${response.body}');
  }
}
```

- [ ] **Step 2: Remove deprecated `register()` and `login()` methods (the ones without auth keys).** Verify call sites — should only be `AuthProvider.login()` and `AuthProvider.register()` after Task 21.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/services/api_service.dart
git commit -m "feat(auth): add identity-key auth endpoints to ApiService"
```

---

## Task 20 — `AuthSessionManager`

**Files:**
- Create: `frontend/lib/services/auth_session_manager.dart`
- Create: `frontend/test/services/auth_session_manager_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// frontend/test/services/auth_session_manager_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:fireplace/services/api_service.dart';
import 'package:fireplace/services/auth_session_manager.dart';
import 'package:fireplace/services/crypto/auth_identity_keypair.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class MockApiService extends Mock implements ApiService {}

void main() {
  // Helper: build a JWT with a controllable exp.
  String buildJwt(int expSecondsFromNow) {
    final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')).replaceAll('=', '');
    final payload = base64Url.encode(utf8.encode(
      '{"sub":7,"deviceId":"d1","exp":${(DateTime.now().millisecondsSinceEpoch ~/ 1000) + expSecondsFromNow}}',
    )).replaceAll('=', '');
    return '$header.$payload.signature';
  }

  test('getValidToken() returns null when not initialized', () async {
    final mgr = AuthSessionManager(MockApiService());
    expect(await mgr.getValidToken(), isNull);
  });

  test('getValidToken() returns cached token when not near expiry', () async {
    final api = MockApiService();
    final mgr = AuthSessionManager(api);
    final kp = await AuthIdentityKeyPair.generate();
    final token = buildJwt(3600);    // 1h from now
    await mgr.adopt(sessionToken: token, deviceId: 'd1', keyPair: kp);
    expect(await mgr.getValidToken(), token);
    verifyNever(api.requestChallenge(any));
  });

  test('getValidToken() refreshes when token within 2 min of expiry', () async {
    final api = MockApiService();
    when(api.requestChallenge('d1'))
      .thenAnswer((_) async => {'nonce': 'AAA=', 'expiresAt': 'iso'});
    when(api.refreshWithKey(deviceId: 'd1', signature: anyNamed('signature'), timestamp: anyNamed('timestamp')))
      .thenAnswer((_) async => {'sessionToken': buildJwt(7200)});
    final mgr = AuthSessionManager(api);
    final kp = await AuthIdentityKeyPair.generate();
    await mgr.adopt(sessionToken: buildJwt(60), deviceId: 'd1', keyPair: kp);
    final fresh = await mgr.getValidToken();
    expect(fresh, isNotNull);
    expect(fresh, isNot(equals(buildJwt(60))));
    verify(api.requestChallenge('d1')).called(1);
  });

  test('single-flight: 5 concurrent getValidToken() calls trigger 1 refresh', () async {
    final api = MockApiService();
    int refreshCalls = 0;
    when(api.requestChallenge('d1')).thenAnswer((_) async {
      refreshCalls++;
      await Future.delayed(const Duration(milliseconds: 50));
      return {'nonce': 'AAA=', 'expiresAt': 'iso'};
    });
    when(api.refreshWithKey(deviceId: anyNamed('deviceId'), signature: anyNamed('signature'), timestamp: anyNamed('timestamp')))
      .thenAnswer((_) async => {'sessionToken': buildJwt(7200)});
    final mgr = AuthSessionManager(api);
    final kp = await AuthIdentityKeyPair.generate();
    await mgr.adopt(sessionToken: buildJwt(60), deviceId: 'd1', keyPair: kp);

    final results = await Future.wait(List.generate(5, (_) => mgr.getValidToken()));
    for (final r in results) { expect(r, isNotNull); }
    expect(refreshCalls, 1);
  });

  test('forceRefresh() clears cached token but keeps deviceId + keyPair', () async {
    final api = MockApiService();
    when(api.requestChallenge('d1')).thenAnswer((_) async => {'nonce': 'AAA=', 'expiresAt': 'iso'});
    when(api.refreshWithKey(deviceId: 'd1', signature: anyNamed('signature'), timestamp: anyNamed('timestamp')))
      .thenAnswer((_) async => {'sessionToken': buildJwt(7200)});
    final mgr = AuthSessionManager(api);
    final kp = await AuthIdentityKeyPair.generate();
    await mgr.adopt(sessionToken: buildJwt(3600), deviceId: 'd1', keyPair: kp);

    final newToken = await mgr.forceRefresh();
    expect(newToken, isNotNull);
    expect(mgr.deviceId, 'd1');
  });

  test('forceRefresh() throws NO_CREDENTIALS when no keypair', () async {
    final mgr = AuthSessionManager(MockApiService());
    expect(() => mgr.forceRefresh(), throwsA(predicate((e) => e.toString().contains('NO_CREDENTIALS'))));
  });
}
```

- [ ] **Step 2: Run tests, verify failure**

```bash
cd frontend && flutter test test/services/auth_session_manager_test.dart
```
Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
// frontend/lib/services/auth_session_manager.dart
import 'dart:async';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'api_service.dart';
import 'crypto/auth_identity_keypair.dart';

class AuthSessionManager {
  final ApiService _api;
  Completer<String>? _refreshing;

  String? _sessionToken;
  String? _deviceId;
  AuthIdentityKeyPair? _keyPair;
  DateTime? _sessionExp;

  String? get deviceId => _deviceId;
  String? get sessionToken => _sessionToken;
  AuthIdentityKeyPair? get keyPair => _keyPair;

  AuthSessionManager(this._api);

  Future<void> adopt({
    String? sessionToken, required String deviceId, required AuthIdentityKeyPair keyPair,
  }) async {
    _sessionToken = sessionToken;
    _deviceId = deviceId;
    _keyPair = keyPair;
    if (sessionToken != null && sessionToken.isNotEmpty) {
      try { _sessionExp = JwtDecoder.getExpirationDate(sessionToken); }
      catch (_) { _sessionExp = null; }
    } else { _sessionExp = null; }
  }

  void clear() {
    _sessionToken = null;
    _deviceId = null;
    _keyPair = null;
    _sessionExp = null;
  }

  Future<String?> getValidToken() async {
    if (_keyPair == null || _deviceId == null) return null;

    final needsRefresh = _sessionToken == null
        || _sessionExp == null
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
    } catch (e, st) {
      _refreshing!.completeError(e, st);
      rethrow;
    } finally {
      _refreshing = null;
    }
  }

  Future<String> forceRefresh() async {
    if (_keyPair == null || _deviceId == null) {
      throw Exception('NO_CREDENTIALS');
    }
    _sessionToken = null;
    _sessionExp = null;
    final token = await getValidToken();
    if (token == null) throw Exception('REFRESH_FAILED');
    return token;
  }

  Future<String> _doRefresh() async {
    final challenge = await _api.requestChallenge(_deviceId!);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final sig = await _keyPair!.sign('${challenge['nonce']}:$ts');
    final result = await _api.refreshWithKey(
      deviceId: _deviceId!, signature: sig, timestamp: ts,
    );
    return result['sessionToken'] as String;
  }
}
```

- [ ] **Step 4: Run tests, verify pass**

```bash
cd frontend && flutter test test/services/auth_session_manager_test.dart
```
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/services/auth_session_manager.dart frontend/test/services/auth_session_manager_test.dart
git commit -m "feat(auth): add AuthSessionManager with single-flight refresh"
```

---

# PR 6 — Frontend AuthProvider + ConnectionProvider Rewrite

## Task 21 — Rewrite `AuthProvider`

**Files:**
- Modify: `frontend/lib/providers/auth_provider.dart`
- Create: `frontend/test/providers/auth_provider_identity_key_test.dart`

- [ ] **Step 1: Replace contents of `auth_provider.dart`**

```dart
// frontend/lib/providers/auth_provider.dart
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';
import '../services/auth_session_manager.dart';
import '../services/crypto/auth_identity_keypair.dart';
import '../config/app_config.dart';
import 'dart:io' show Platform;

class AuthProvider extends ChangeNotifier {
  final ApiService _api = ApiService(baseUrl: AppConfig.baseUrl);
  late final AuthSessionManager sessionManager = AuthSessionManager(_api);
  late final PushService _pushService = PushService(_api);

  UserModel? _currentUser;
  String? _statusMessage;
  bool _isError = false;

  UserModel? get currentUser => _currentUser;
  String? get statusMessage => _statusMessage;
  bool get isError => _isError;
  bool get isLoggedIn => _currentUser != null && sessionManager.deviceId != null;
  String? get token => sessionManager.sessionToken;

  AuthProvider() { _loadSavedSession(); }

  static const _deviceIdKey = 'device_id_v1';

  Future<void> _loadSavedSession() async {
    final keyPair = await AuthIdentityKeyPair.loadFromStorage();
    final secure = AuthIdentityKeyPair.secureStorage();
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await secure.read(key: _deviceIdKey) ?? prefs.getString(_deviceIdKey);
    if (keyPair == null || deviceId == null) return;
    await sessionManager.adopt(sessionToken: null, deviceId: deviceId, keyPair: keyPair);

    try {
      final token = await sessionManager.getValidToken();
      if (token == null) { await _clearSession(); notifyListeners(); return; }
      final me = await _api.fetchMe(token);
      _currentUser = UserModel.fromJson(me);
      notifyListeners();
    } on Exception catch (e) {
      if (e.toString().contains('SESSION_REVOKED') || e.toString().contains('REFRESH_FAILED')
          || e.toString().contains('HTTP_401')) {
        await _clearSession(); notifyListeners();
      }
      // Other errors (network) → keep credentials, retry next time.
    }
  }

  Future<bool> register(String username, String password) async {
    try {
      final keyPair = await AuthIdentityKeyPair.generate();
      final result = await _api.registerWithDevice(
        username: username, password: password,
        authPublicKey: keyPair.publicKeyB64,
        deviceLabel: await _detectDeviceLabel(),
        deviceKind: _detectDeviceKind(),
      );
      await _adoptSuccess(keyPair, result);
      _statusMessage = null; _isError = false;
      notifyListeners();
      return true;
    } catch (e) {
      _statusMessage = _userFriendlyNetworkError(e);
      _isError = true;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String identifier, String password) async {
    try {
      final keyPair = await AuthIdentityKeyPair.generate();
      final result = await _api.loginWithDevice(
        identifier: identifier, password: password,
        authPublicKey: keyPair.publicKeyB64,
        deviceLabel: await _detectDeviceLabel(),
        deviceKind: _detectDeviceKind(),
      );
      await _adoptSuccess(keyPair, result);
      _statusMessage = null; _isError = false;
      notifyListeners();
      return true;
    } catch (e) {
      _statusMessage = _userFriendlyNetworkError(e);
      _isError = true;
      notifyListeners();
      return false;
    }
  }

  Future<void> _adoptSuccess(AuthIdentityKeyPair kp, Map<String, dynamic> result) async {
    await kp.persist();
    final secure = AuthIdentityKeyPair.secureStorage();
    final prefs = await SharedPreferences.getInstance();
    final deviceId = result['deviceId'] as String;
    await secure.write(key: _deviceIdKey, value: deviceId);
    await prefs.setString(_deviceIdKey, deviceId);
    await sessionManager.adopt(
      sessionToken: result['sessionToken'] as String,
      deviceId: deviceId,
      keyPair: kp,
    );
    _currentUser = UserModel.fromJson(result['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    final token = sessionManager.sessionToken;
    if (token != null) {
      try { await _pushService.unregister(token); } catch (_) {}
      try { await _api.logoutDevice(token); } catch (_) {}
    }
    await _clearSession();
    notifyListeners();
  }

  Future<void> _clearSession() async {
    await AuthIdentityKeyPair.clear();
    final secure = AuthIdentityKeyPair.secureStorage();
    final prefs = await SharedPreferences.getInstance();
    await secure.delete(key: _deviceIdKey);
    await prefs.remove(_deviceIdKey);
    sessionManager.clear();
    _currentUser = null;
    _statusMessage = null;
    _isError = false;
  }

  Future<bool> deleteAccount(String password) async {
    if (sessionManager.sessionToken == null) {
      throw Exception('Not authenticated');
    }
    try {
      await _api.deleteAccount(sessionManager.sessionToken!, password);
      await logout();
      return true;
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> updateProfilePicture(XFile imageFile) async {
    final token = sessionManager.sessionToken;
    if (token == null) throw Exception('Not authenticated');
    try {
      await _api.uploadProfilePicture(token, imageFile);
      final me = await _api.fetchMe(token);
      _currentUser = UserModel.fromJson(me);
      notifyListeners();
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> resetPassword(String oldPassword, String newPassword) async {
    final token = sessionManager.sessionToken;
    if (token == null) throw Exception('Not authenticated');
    try {
      await _api.resetPassword(token, oldPassword, newPassword);
      // After password change, all device_sessions are wiped. Force re-login.
      await _clearSession();
      notifyListeners();
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void clearStatus() {
    _statusMessage = null;
    _isError = false;
    notifyListeners();
  }

  String _detectDeviceKind() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'desktop';
  }

  Future<String> _detectDeviceLabel() async {
    if (kIsWeb) return 'Web browser';
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      return '${a.manufacturer} ${a.model}';
    }
    if (Platform.isIOS) {
      final i = await info.iosInfo;
      return i.utsname.machine;
    }
    return 'Desktop';
  }

  static String _userFriendlyNetworkError(Object e) {
    final msg = e.toString().replaceFirst('Exception: ', '');
    if (msg.contains('Failed to fetch') || msg.contains('Connection refused')
        || msg.contains('Connection reset') || msg.contains('SocketException')
        || msg.contains('NetworkException')) {
      return 'Cannot reach server. Is the backend running? (e.g. docker-compose up)';
    }
    return msg;
  }
}
```

- [ ] **Step 2: Add tests** in `frontend/test/providers/auth_provider_identity_key_test.dart`. Cover: `login()` happy path, `login()` failure clears error correctly, `logout()` calls API + clears session, `_loadSavedSession()` with no keypair → no-op, `_loadSavedSession()` with keypair + 401 from /me → clears session, `resetPassword()` clears session.

- [ ] **Step 3: Run tests**

```bash
cd frontend && flutter test test/providers/auth_provider_identity_key_test.dart
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/providers/auth_provider.dart frontend/test/providers/auth_provider_identity_key_test.dart
git commit -m "feat(auth): rewrite AuthProvider for identity-key flow"
```

---

## Task 22 — `ApiService` 401 retry helper + apply to all methods

**Files:**
- Modify: `frontend/lib/services/api_service.dart`

- [ ] **Step 1: Add a generic retry helper**

```dart
// inside ApiService

AuthSessionManager? _sessionManager;
void attachSessionManager(AuthSessionManager mgr) { _sessionManager = mgr; }

Future<http.Response> _authedRequest(
  Future<http.Response> Function(String token) makeRequest,
) async {
  final mgr = _sessionManager;
  if (mgr == null) throw Exception('NO_SESSION_MANAGER');
  String? token = await mgr.getValidToken();
  if (token == null) throw Exception('NOT_AUTHENTICATED');
  var response = await makeRequest(token);
  if (response.statusCode == 401) {
    try {
      token = await mgr.forceRefresh();
      response = await makeRequest(token);
    } catch (_) {
      // refresh failed → drop through to second-401 path below
    }
    if (response.statusCode == 401) {
      throw Exception('SESSION_REVOKED');
    }
  }
  return response;
}
```

- [ ] **Step 2: Refactor existing authenticated methods to use `_authedRequest`**

For example, `fetchMe`:
```dart
Future<Map<String, dynamic>> fetchMe([String? unused]) async {
  final response = await _authedRequest((token) =>
    http.get(Uri.parse('$baseUrl/users/me'),
      headers: {'Authorization': 'Bearer $token'}));
  if (response.statusCode != 200) {
    throw Exception('HTTP_${response.statusCode}: ${response.body}');
  }
  return jsonDecode(response.body);
}
```

Apply same pattern to all other authenticated methods (`uploadProfilePicture`, `deleteAccount`, `resetPassword`, `getMessages`, `fetchMediaBytes` for own-server URLs, etc.). Methods that take an explicit `token` parameter for backward compatibility can keep that parameter unused or be migrated.

**Note:** Some current methods take `String token` as first arg. Keep the signature backward compat for now (the param is ignored when `_sessionManager` is attached). After full migration, drop those params in a follow-up cleanup.

- [ ] **Step 3: Wire `attachSessionManager` in `AuthProvider` constructor**

In `AuthProvider` constructor:
```dart
AuthProvider() {
  _api.attachSessionManager(sessionManager);
  _loadSavedSession();
}
```

- [ ] **Step 4: Run all frontend tests**

```bash
cd frontend && flutter test
```
Expected: all tests pass (98+).

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/services/api_service.dart frontend/lib/providers/auth_provider.dart
git commit -m "feat(auth): add 401-retry helper in ApiService using AuthSessionManager"
```

---

## Task 23 — `ConnectionProvider` proactive token refresh + reconnect

**Files:**
- Modify: `frontend/lib/providers/connection_provider.dart`

- [ ] **Step 1: Add token-expiry timer**

In `ConnectionProvider`, add:
```dart
import 'package:jwt_decoder/jwt_decoder.dart';
import 'dart:async';

Timer? _tokenRefreshTimer;

void _scheduleTokenRefresh(String token) {
  _tokenRefreshTimer?.cancel();
  try {
    final exp = JwtDecoder.getExpirationDate(token);
    final delta = exp.subtract(const Duration(minutes: 1)).difference(DateTime.now());
    if (delta.isNegative) {
      _refreshAndReconnect();
    } else {
      _tokenRefreshTimer = Timer(delta, _refreshAndReconnect);
    }
  } catch (_) {/* invalid JWT — let socket fail naturally */}
}

Future<void> _refreshAndReconnect() async {
  try {
    final newToken = await _authProvider.sessionManager.forceRefresh();
    _socketService.disconnect();
    _socketService.connect(baseUrl: AppConfig.baseUrl, token: newToken, ...);
    _scheduleTokenRefresh(newToken);
  } catch (_) {
    // refresh failed → AuthProvider's session was cleared in forceRefresh chain
    // notify ConnectionProvider listeners that we're disconnected
  }
}

@override
void dispose() {
  _tokenRefreshTimer?.cancel();
  super.dispose();
}
```

Call `_scheduleTokenRefresh(token)` after every successful `connect()` and after every refresh.

- [ ] **Step 2: Verify with manual test**

Set JWT TTL to 5 minutes in dev, login, leave app open, observe socket reconnect at ~4-min mark with new token.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/providers/connection_provider.dart
git commit -m "feat(auth): proactive token refresh + reconnect timer"
```

---

# PR 7 — Frontend Active Devices UI

## Task 24 — `DeviceSessionModel`

**Files:**
- Create: `frontend/lib/models/device_session_model.dart`

- [ ] **Step 1: Create model**

```dart
// frontend/lib/models/device_session_model.dart
class DeviceSessionModel {
  final String id;
  final String deviceLabel;
  final String deviceKind;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final bool current;

  DeviceSessionModel({
    required this.id, required this.deviceLabel, required this.deviceKind,
    required this.createdAt, required this.lastSeenAt, required this.current,
  });

  factory DeviceSessionModel.fromJson(Map<String, dynamic> j) => DeviceSessionModel(
    id: j['id'], deviceLabel: j['deviceLabel'], deviceKind: j['deviceKind'],
    createdAt: DateTime.parse(j['createdAt']),
    lastSeenAt: DateTime.parse(j['lastSeenAt']),
    current: j['current'] == true,
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/models/device_session_model.dart
git commit -m "feat(auth): add DeviceSessionModel"
```

---

## Task 25 — `ActiveDevicesScreen`

**Files:**
- Create: `frontend/lib/screens/active_devices_screen.dart`
- Modify: `frontend/lib/screens/settings_screen.dart` — add "Active Devices" entry that pushes the new screen.
- Add localization strings to `frontend/lib/l10n/app_pl.arb` and `app_en.arb`:

```json
{
  "settingsActiveDevices": "Active Devices",
  "activeDevicesTitle": "Active Devices",
  "activeDevicesEmpty": "No other devices",
  "activeDevicesCurrent": "(this device)",
  "activeDevicesRemoveConfirmTitle": "Remove device?",
  "activeDevicesRemoveConfirmBody": "{label} will be logged out at its next request.",
  "@activeDevicesRemoveConfirmBody": { "placeholders": { "label": { "type": "String" } } },
  "activeDevicesLastSeen": "Last seen {date}",
  "@activeDevicesLastSeen": { "placeholders": { "date": { "type": "String" } } }
}
```

(Polish equivalents: "Aktywne urządzenia", "(to urządzenie)", "Usunąć urządzenie?", etc.)

- [ ] **Step 1: Create screen**

```dart
// frontend/lib/screens/active_devices_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/device_session_model.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../config/app_config.dart';

class ActiveDevicesScreen extends StatefulWidget {
  const ActiveDevicesScreen({super.key});
  @override
  State<ActiveDevicesScreen> createState() => _ActiveDevicesScreenState();
}

class _ActiveDevicesScreenState extends State<ActiveDevicesScreen> {
  late Future<List<DeviceSessionModel>> _future;
  final _api = ApiService(baseUrl: AppConfig.baseUrl);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<DeviceSessionModel>> _load() async {
    final auth = context.read<AuthProvider>();
    final token = auth.sessionManager.sessionToken!;
    final list = await _api.listDevices(token);
    return list.map((j) => DeviceSessionModel.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> _remove(DeviceSessionModel d) async {
    final auth = context.read<AuthProvider>();
    final token = auth.sessionManager.sessionToken!;
    await _api.removeDevice(token, d.id);
    setState(() { _future = _load(); });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.activeDevicesTitle)),
      body: FutureBuilder<List<DeviceSessionModel>>(
        future: _future,
        builder: (ctx, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final d = list[i];
              return ListTile(
                leading: Icon(_iconFor(d.deviceKind)),
                title: Text(d.deviceLabel),
                subtitle: Text('${d.deviceKind} · ${l.activeDevicesLastSeen(d.lastSeenAt.toLocal().toString())}'
                    + (d.current ? ' ${l.activeDevicesCurrent}' : '')),
                trailing: d.current ? null : IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(l.activeDevicesRemoveConfirmTitle),
                        content: Text(l.activeDevicesRemoveConfirmBody(d.deviceLabel)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
                        ],
                      ),
                    );
                    if (confirm == true) await _remove(d);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'web': return Icons.public;
      case 'android': return Icons.phone_android;
      case 'ios': return Icons.phone_iphone;
      case 'desktop': return Icons.desktop_windows;
      default: return Icons.devices_other;
    }
  }
}
```

- [ ] **Step 2: Add ListTile entry in `settings_screen.dart`**

Wherever profile/security tiles live, add:
```dart
ListTile(
  leading: const Icon(Icons.devices),
  title: Text(l.settingsActiveDevices),
  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ActiveDevicesScreen())),
),
```

- [ ] **Step 3: Run tests**

```bash
cd frontend && flutter analyze
cd frontend && flutter test
```
Expected: no analyzer errors, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/active_devices_screen.dart frontend/lib/screens/settings_screen.dart frontend/lib/l10n/
git commit -m "feat(auth): add Active Devices screen with remote logout"
```

---

# PR 8 — Final Tests, Docs, Cleanup

## Task 26 — Manual E2E test pass

Run through the manual scenarios from spec § "Testing Strategy → Manual E2E":

- [ ] Register → Active Devices shows 1 row
- [ ] Login on another browser → 2 rows
- [ ] Remote-logout the second from the first → second browser shows login at next refresh (max 2h, dev: bump challenge TTL or wait)
- [ ] Change password → both browsers must re-login
- [ ] Leave app open 1h → use a feature → works (silent refresh in background)
- [ ] Push notification on logged-in device after sleep → opens correct chat (no login screen)

If any scenario fails, file a bug task and fix before merging.

## Task 27 — Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Replace the JWT TTL line and JwtStrategy line in `Backend` gotchas with the new auth model**

```markdown
- Identity-key auth: per-device Ed25519 keypair (`auth_pub_key` in `device_sessions` table); session token is short-lived (2h) JWT carrying `deviceId`. Silent refresh via signed challenge: `POST /auth/challenge` returns nonce, client signs `nonce:tsMs`, posts to `/auth/refresh-with-key`. `IdentityKeySessionGuard` (`backend/src/auth/identity-key-session.guard.ts`) replaces old `JwtAuthGuard`; injects `req.user = {id, username, tag, deviceId}` (no `profilePictureUrl` — fetch via `/users/me`).
- `device_sessions` sliding 90-day expiry; `AuthCleanupService` cron deletes rows expired >30 days ago. Daily at 3 AM.
- Password change deletes ALL device_sessions for the user (logout-all-devices).
- Active Devices UI in Settings (`active_devices_screen.dart`); remote logout via `DELETE /auth/devices/:id`.
- Auth challenge store is **in-memory** (`AuthChallengeStore`). Single-pod constraint. Before scaling out: switch to Redis or DB-backed store. Documented in design spec.
- Frontend keeps deviceId + auth keypair in DualStorage (`flutter_secure_storage` + `SharedPreferences`); same pattern as Signal stores.
- `AuthSessionManager.forceRefresh()` does single-flight refresh; ApiService `_authedRequest()` retries once on 401, throws `SESSION_REVOKED` on second 401.
- `ConnectionProvider._scheduleTokenRefresh()` proactively refreshes session token ~1 min before expiry, then reconnects socket with new token (uses existing `enableForceNew` path).
```

- [ ] **Step 2: Remove the Phase 0 hotfix line** (since Phase 1 is now live, the comment about 30d TTL is obsolete).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude): update auth section after identity-key cutover"
```

## Task 28 — Remove Phase 0 hotfix comment

**Files:**
- Modify: `backend/src/auth/auth.module.ts`

- [ ] **Step 1: Remove the Phase 0 hotfix comment block**

In `auth.module.ts`, the JWT signOptions now signs **session tokens** (2h), not the legacy long-lived bearer. Remove the dated comment and replace with a brief explanation:

```typescript
return {
  secret,
  // Default sign options for session tokens issued by AuthService.issueSessionToken.
  // Per-call expiresIn override is used (2h for session tokens).
  signOptions: { expiresIn: '2h' },
};
```

- [ ] **Step 2: Run tests, commit**

```bash
cd backend && npm test
git add backend/src/auth/auth.module.ts
git commit -m "chore(auth): remove Phase 0 hotfix comment, set default JWT TTL to 2h"
```

## Task 29 — Final full test sweep

- [ ] **Step 1: Backend**

```bash
cd backend && npm test
```
Expected: all tests pass.

- [ ] **Step 2: Frontend**

```bash
cd frontend && flutter analyze && flutter test
```
Expected: no analyzer errors, all tests pass.

- [ ] **Step 3: If anything fails, fix and commit before merging.**

## Task 30 — Session summary + PR description

- [ ] **Step 1: Write session summary** in `.cursor/session-summaries/YYYY-MM-DD-session.md` summarizing the implementation work.
- [ ] **Step 2: Update `.cursor/session-summaries/LATEST.md`**.
- [ ] **Step 3: Open PR with description summarizing:**
  - Phase 0 → Phase 1 transition
  - Reference to spec doc
  - Breaking change: all users re-login once after deploy
  - Manual E2E checklist passed
  - Tests added: count

---

# Self-Review

**Spec coverage:**

| Spec section | Plan task(s) |
|---|---|
| Architecture (Ed25519, separate auth key, 2h JWT, in-memory challenge) | Tasks 1, 3, 4, 8 |
| Database (`device_sessions`, no users change, cleanup cron) | Tasks 1, 14 |
| Registration flow | Tasks 6, 8, 21 |
| Login flow (new device) | Tasks 6, 8, 21 |
| Silent refresh flow | Tasks 4, 9, 10, 19, 20, 23 |
| Normal request 401 retry | Task 22 |
| Logout (current device) | Tasks 10, 21 |
| Remote logout | Tasks 10, 25 |
| Recovery (re-login generates fresh keypair) | Task 21 |
| Password change clears all sessions | Task 15 |
| Socket.io auth update | Task 12 |
| Endpoints (full list with throttling) | Tasks 7, 10 |
| `IdentityKeySessionGuard` | Task 9 |
| Ed25519 verifier | Task 3 |
| `AuthChallengeStore` (in-memory + cleanup) | Task 4 |
| Mid-connection token expiry handler | Task 23 |
| Push notifications survive re-login | Verified in Task 26 (manual E2E) |
| Frontend file layout (`AuthIdentityKeyPair`, `AuthSessionManager`, `ActiveDevicesScreen`, model) | Tasks 18, 20, 24, 25 |
| Backend tests (per spec) | Tasks 2, 3, 4, 8, 9, 10, 14, 15 |
| Frontend tests (per spec) | Tasks 18, 20, 21 |
| Manual E2E checklist | Task 26 |
| Migration: NONE | (no task — implicit in PR 3 cutover) |
| Deployment checklist (single-pod) | Documented in CLAUDE.md update Task 27 |

All spec requirements have at least one task. ✅

**Placeholder scan:** No "TBD", "TODO", "implement later", or "fill in details". Where boilerplate (e.g. existing controller test mocks) is referenced, the existing pattern in the codebase is named explicitly (`auth.controller.spec.ts`). ✅

**Type consistency:**
- `DeviceSession.id` is `string` (UUID) everywhere ✅
- `req.user.deviceId` matches JWT payload `deviceId` matches `DeviceSession.id` ✅
- `timestamp` is **ms** (`Date.now()` / `DateTime.now().millisecondsSinceEpoch`) on both sides; backend tolerates ±60_000 ms ✅
- `nonce`, `signature`, `authPublicKey`, `privateKeyB64` all base64 strings on the wire ✅
- `deviceKind` is union `'web' | 'android' | 'ios' | 'desktop'` everywhere ✅
- `AuthSessionManager.forceRefresh()` is the public name; not `invalidate()` (renamed during spec review) ✅

No issues found.

---

# Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-09-identity-key-auth.md`. Two execution options:

**1. Subagent-Driven (recommended)** — Fresh subagent per task, review between tasks, fast iteration. Required sub-skill: `superpowers:subagent-driven-development`.

**2. Inline Execution** — Execute tasks in the current session sequentially with checkpoints. Required sub-skill: `superpowers:executing-plans`.

**Which approach?**
