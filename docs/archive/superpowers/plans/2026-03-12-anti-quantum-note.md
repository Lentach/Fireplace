# Anti-Quantum Note — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 7th chat action tile that creates a client-side AES-encrypted self-destructing note, sends it as a one-time URL in the conversation, and serves a minimal HTML reading page from the backend.

**Architecture:** Flutter encrypts note content with AES-GCM locally, sends only ciphertext to backend. Backend stores ciphertext + token in a new `secret_notes` PostgreSQL table. Reading page JS decrypts using the key embedded in the URL fragment (`#KEY`) — server never sees the key. Hard DELETE after first reveal click.

**Tech Stack:** NestJS (TypeORM, express), Flutter (`encrypt` package for AES-GCM), Web Crypto API (browser, no external JS libs), PostgreSQL.

---

## Chunk 1: Backend — Entity, Module, Service

### Task 1: SecretNote entity

**Files:**
- Create: `backend/src/secret-notes/secret-note.entity.ts`

- [ ] **Step 1: Create the entity file**

```typescript
// backend/src/secret-notes/secret-note.entity.ts
import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn } from 'typeorm';

@Entity('secret_notes')
export class SecretNote {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ unique: true, length: 64 })
  token: string;

  @Column({ type: 'text' })
  ciphertext: string;

  @Column({ type: 'timestamp' })
  expiresAt: Date;

  @Column({ nullable: true })
  creatorId: number;

  @CreateDateColumn()
  createdAt: Date;
}
```

- [ ] **Step 2: Commit**

```bash
git add backend/src/secret-notes/secret-note.entity.ts
git commit -m "feat: add SecretNote entity"
```

---

### Task 2: SecretNotesService

**Files:**
- Create: `backend/src/secret-notes/secret-notes.service.ts`
- Create: `backend/src/secret-notes/secret-notes.service.spec.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// backend/src/secret-notes/secret-notes.service.spec.ts
import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { SecretNotesService } from './secret-notes.service';
import { SecretNote } from './secret-note.entity';

const mockRepo = () => ({
  create: jest.fn(),
  save: jest.fn(),
  findOne: jest.fn(),
  delete: jest.fn(),
});

describe('SecretNotesService', () => {
  let service: SecretNotesService;
  let repo: ReturnType<typeof mockRepo>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        SecretNotesService,
        { provide: getRepositoryToken(SecretNote), useFactory: mockRepo },
      ],
    }).compile();

    service = module.get(SecretNotesService);
    repo = module.get(getRepositoryToken(SecretNote));
  });

  describe('create', () => {
    it('returns a token and saves the note', async () => {
      const note = { token: 'abc123', ciphertext: 'enc', expiresAt: new Date(), creatorId: 1 };
      repo.create.mockReturnValue(note);
      repo.save.mockResolvedValue(note);

      const result = await service.create('enc', 7200, 1);

      expect(repo.save).toHaveBeenCalled();
      expect(result.token).toHaveLength(32);
    });
  });

  describe('revealAndDelete', () => {
    it('returns ciphertext and deletes the note when valid', async () => {
      const future = new Date(Date.now() + 60000);
      const note = { id: 1, token: 'tok', ciphertext: 'enc', expiresAt: future };
      repo.findOne.mockResolvedValue(note);
      repo.delete.mockResolvedValue({});

      const result = await service.revealAndDelete('tok');

      expect(result).toEqual({ ciphertext: 'enc' });
      expect(repo.delete).toHaveBeenCalledWith({ token: 'tok' });
    });

    it('returns null when note not found', async () => {
      repo.findOne.mockResolvedValue(null);
      const result = await service.revealAndDelete('missing');
      expect(result).toBeNull();
    });

    it('returns null and deletes when note is expired', async () => {
      const past = new Date(Date.now() - 1000);
      const note = { id: 1, token: 'tok', ciphertext: 'enc', expiresAt: past };
      repo.findOne.mockResolvedValue(note);
      repo.delete.mockResolvedValue({});

      const result = await service.revealAndDelete('tok');

      expect(result).toBeNull();
      expect(repo.delete).toHaveBeenCalledWith({ token: 'tok' });
    });

  });

  describe('findByToken', () => {
    it('returns null when note is expired', async () => {
      const past = new Date(Date.now() - 1000);
      repo.findOne.mockResolvedValue({ id: 1, token: 'tok', expiresAt: past });
      repo.delete.mockResolvedValue({});

      const result = await service.findByToken('tok');
      expect(result).toBeNull();
      expect(repo.delete).toHaveBeenCalledWith({ token: 'tok' });
    });

    it('returns note when valid', async () => {
      const future = new Date(Date.now() + 60000);
      const note = { id: 1, token: 'tok', ciphertext: 'enc', expiresAt: future };
      repo.findOne.mockResolvedValue(note);

      const result = await service.findByToken('tok');
      expect(result).toBe(note);
    });
  });
});
```

- [ ] **Step 2: Run test — verify it fails**

```bash
cd backend && npx jest secret-notes.service.spec --no-coverage 2>&1 | tail -20
```

Expected: FAIL — `SecretNotesService` not found.

- [ ] **Step 3: Write the service**

```typescript
// backend/src/secret-notes/secret-notes.service.ts
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SecretNote } from './secret-note.entity';
import * as crypto from 'crypto';

@Injectable()
export class SecretNotesService {
  constructor(
    @InjectRepository(SecretNote)
    private readonly repo: Repository<SecretNote>,
  ) {}

  async create(ciphertext: string, expiresInSeconds: number, creatorId: number): Promise<{ token: string }> {
    const token = crypto.randomBytes(16).toString('hex'); // 32-char hex
    const expiresAt = new Date(Date.now() + expiresInSeconds * 1000);
    const note = this.repo.create({ token, ciphertext, expiresAt, creatorId });
    await this.repo.save(note);
    return { token };
  }

  async findByToken(token: string): Promise<SecretNote | null> {
    const note = await this.repo.findOne({ where: { token } });
    if (!note) return null;
    if (new Date(note.expiresAt).getTime() < Date.now()) {
      await this.repo.delete({ token });
      return null;
    }
    return note;
  }

  async revealAndDelete(token: string): Promise<{ ciphertext: string } | null> {
    const note = await this.repo.findOne({ where: { token } });
    if (!note) return null;
    const isExpired = new Date(note.expiresAt).getTime() < Date.now();
    await this.repo.delete({ token });
    if (isExpired) return null;
    return { ciphertext: note.ciphertext };
  }
}
```

- [ ] **Step 4: Run test — verify it passes**

```bash
cd backend && npx jest secret-notes.service.spec --no-coverage 2>&1 | tail -10
```

Expected: PASS — all 5 tests green.

- [ ] **Step 5: Commit**

```bash
git add backend/src/secret-notes/secret-notes.service.ts backend/src/secret-notes/secret-notes.service.spec.ts
git commit -m "feat: add SecretNotesService with create, findByToken, revealAndDelete"
```

---

## Chunk 2: Backend — Controller, Module, App wiring

### Task 3: SecretNotesController

**Files:**
- Create: `backend/src/secret-notes/secret-notes.controller.ts`
- Create: `backend/src/secret-notes/secret-notes.controller.spec.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// backend/src/secret-notes/secret-notes.controller.spec.ts
import { Test } from '@nestjs/testing';
import { SecretNotesController } from './secret-notes.controller';
import { SecretNotesService } from './secret-notes.service';

const mockService = () => ({
  create: jest.fn(),
  findByToken: jest.fn(),
  revealAndDelete: jest.fn(),
});

const mockUser = { userId: 1 };
const mockRes = () => {
  const res: any = {};
  res.send = jest.fn().mockReturnValue(res);
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res;
};

describe('SecretNotesController', () => {
  let controller: SecretNotesController;
  let service: ReturnType<typeof mockService>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      controllers: [SecretNotesController],
      providers: [{ provide: SecretNotesService, useFactory: mockService }],
    }).compile();

    controller = module.get(SecretNotesController);
    service = module.get(SecretNotesService);
  });

  describe('createNote', () => {
    it('returns token for valid request', async () => {
      service.create.mockResolvedValue({ token: 'abc123' });
      const result = await controller.createNote(
        { ciphertext: 'enc', expiresIn: 7200 },
        { user: mockUser },
      );
      expect(result).toEqual({ token: 'abc123' });
      expect(service.create).toHaveBeenCalledWith('enc', 7200, 1);
    });
  });

  describe('getNotePage', () => {
    it('sends HTML when note exists', async () => {
      const future = new Date(Date.now() + 60000);
      service.findByToken.mockResolvedValue({ token: 'tok', expiresAt: future });
      const res = mockRes();
      await controller.getNotePage('tok', res);
      expect(res.send).toHaveBeenCalled();
      const html = res.send.mock.calls[0][0];
      expect(html).toContain('Reveal');
    });

    it('sends destroyed HTML when note not found', async () => {
      service.findByToken.mockResolvedValue(null);
      const res = mockRes();
      await controller.getNotePage('missing', res);
      expect(res.send).toHaveBeenCalled();
      const html = res.send.mock.calls[0][0];
      expect(html).toContain('no longer exists');
    });
  });

  describe('revealNote', () => {
    it('returns ciphertext when note exists', async () => {
      service.revealAndDelete.mockResolvedValue({ ciphertext: 'enc' });
      const res = mockRes();
      await controller.revealNote('tok', res);
      expect(res.json).toHaveBeenCalledWith({ ciphertext: 'enc' });
    });

    it('returns 404 when note gone', async () => {
      service.revealAndDelete.mockResolvedValue(null);
      const res = mockRes();
      await controller.revealNote('missing', res);
      expect(res.status).toHaveBeenCalledWith(404);
    });
  });
});
```

- [ ] **Step 2: Run test — verify it fails**

```bash
cd backend && npx jest secret-notes.controller.spec --no-coverage 2>&1 | tail -10
```

Expected: FAIL — controller not found.

- [ ] **Step 3: Write the controller**

```typescript
// backend/src/secret-notes/secret-notes.controller.ts
import {
  Controller, Post, Get, Body, Param, Req, Res, UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SecretNotesService } from './secret-notes.service';
import { Response } from 'express';

class CreateNoteDto {
  ciphertext: string;
  expiresIn: number; // seconds: 7200 | 21600 | 43200
}

@Controller()
export class SecretNotesController {
  constructor(private readonly service: SecretNotesService) {}

  @UseGuards(JwtAuthGuard)
  @Post('notes')
  async createNote(@Body() dto: CreateNoteDto, @Req() req: any) {
    const validTtls = [7200, 21600, 43200];
    const expiresIn = validTtls.includes(dto.expiresIn) ? dto.expiresIn : 21600;
    return this.service.create(dto.ciphertext, expiresIn, req.user.userId);
  }

  @Get('note/:token')
  async getNotePage(@Param('token') token: string, @Res() res: Response) {
    const note = await this.service.findByToken(token);
    if (!note) {
      res.send(this.destroyedPage());
      return;
    }
    const remainingMs = new Date(note.expiresAt).getTime() - Date.now();
    const remainingLabel = this.formatRemaining(remainingMs);
    res.send(this.landingPage(token, remainingLabel));
  }

  @Post('note/:token/reveal')
  async revealNote(@Param('token') token: string, @Res() res: Response) {
    const result = await this.service.revealAndDelete(token);
    if (!result) {
      res.status(404).json({ error: 'gone' });
      return;
    }
    res.json({ ciphertext: result.ciphertext });
  }

  private formatRemaining(ms: number): string {
    const h = Math.floor(ms / 3600000);
    const m = Math.floor((ms % 3600000) / 60000);
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
  }

  private landingPage(token: string, remaining: string): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Anti-Quantum Note</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{background:#111;color:#eee;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
    display:flex;align-items:center;justify-content:center;min-height:100vh;padding:20px}
  .card{background:#1e1e1e;border-radius:16px;padding:36px 28px;max-width:440px;width:100%;text-align:center;
    box-shadow:0 8px 32px rgba(0,0,0,0.5)}
  .icon{font-size:48px;margin-bottom:16px}
  h1{font-size:20px;font-weight:700;margin-bottom:8px;letter-spacing:0.3px}
  .sub{color:#888;font-size:14px;line-height:1.6;margin-bottom:28px}
  .btn{background:linear-gradient(135deg,#c0392b,#922b21);border:none;border-radius:10px;
    color:#fff;font-size:15px;font-weight:700;padding:14px 32px;cursor:pointer;width:100%;
    letter-spacing:0.3px;transition:opacity 0.2s}
  .btn:hover{opacity:0.9}
  .btn:disabled{opacity:0.5;cursor:not-allowed}
  .expires{color:#555;font-size:12px;margin-top:16px}
  .content{background:#151515;border:1px solid #333;border-radius:10px;padding:20px;
    text-align:left;line-height:1.7;font-size:14px;color:#ddd;word-break:break-word;
    white-space:pre-wrap;margin-bottom:16px}
  .revealed-header{color:#888;font-size:11px;text-transform:uppercase;letter-spacing:1px;margin-bottom:16px}
  .footer{color:#444;font-size:11px;margin-top:12px}
  #error{color:#e74c3c;font-size:13px;margin-top:12px;display:none}
</style>
</head>
<body>
<div class="card" id="landing">
  <div class="icon">⚛️</div>
  <h1>Anti-Quantum Note</h1>
  <p class="sub">Someone sent you a self-destructing message.<br>It will be permanently destroyed after you read it.</p>
  <button class="btn" id="revealBtn" onclick="reveal()">🔓 Reveal &amp; Destroy</button>
  <div class="expires">Expires in ${remaining} · Powered by Fireplace</div>
  <div id="error">Failed to load note. It may have already been read.</div>
</div>

<div class="card" id="revealed" style="display:none">
  <div class="icon">🔓</div>
  <div class="revealed-header">Message revealed · Now permanently destroyed</div>
  <div class="content" id="noteContent"></div>
  <div class="footer">This note has been deleted from the server.<br>Refreshing this page will show nothing.</div>
</div>

<script>
async function reveal() {
  const btn = document.getElementById('revealBtn');
  btn.disabled = true;
  btn.textContent = 'Decrypting...';

  try {
    const fragment = location.hash.slice(1);
    if (!fragment) throw new Error('No key in URL');

    const res = await fetch('/note/${token}/reveal', { method: 'POST' });
    if (!res.ok) throw new Error('gone');
    const { ciphertext } = await res.json();

    const keyBytes = base64ToBytes(fragment);
    const cryptoKey = await crypto.subtle.importKey(
      'raw', keyBytes, { name: 'AES-GCM' }, false, ['decrypt']
    );

    const parts = ciphertext.split(':');
    if (parts.length !== 2) throw new Error('bad format');
    const iv = base64ToBytes(parts[0]);
    const enc = base64ToBytes(parts[1]);

    const decrypted = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, cryptoKey, enc);
    const text = new TextDecoder().decode(decrypted);

    document.getElementById('landing').style.display = 'none';
    document.getElementById('noteContent').textContent = text;
    document.getElementById('revealed').style.display = '';
  } catch (e) {
    btn.disabled = false;
    btn.textContent = '🔓 Reveal & Destroy';
    document.getElementById('error').style.display = '';
  }
}

function base64ToBytes(b64) {
  const bin = atob(b64.replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from(bin, c => c.charCodeAt(0));
}
</script>
</body>
</html>`;
  }

  private destroyedPage(): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Anti-Quantum Note</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{background:#111;color:#eee;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
    display:flex;align-items:center;justify-content:center;min-height:100vh}
  .card{background:#1e1e1e;border-radius:16px;padding:36px 28px;max-width:440px;width:100%;
    text-align:center;box-shadow:0 8px 32px rgba(0,0,0,0.5)}
  .icon{font-size:48px;margin-bottom:16px}
  h1{font-size:18px;font-weight:700;margin-bottom:10px}
  p{color:#666;font-size:14px;line-height:1.6}
</style>
</head>
<body>
<div class="card">
  <div class="icon">💀</div>
  <h1>This note no longer exists</h1>
  <p>It was either already read or has expired.<br>Ask the sender to create a new one.</p>
</div>
</body>
</html>`;
  }
}
```

- [ ] **Step 4: Run test — verify it passes**

```bash
cd backend && npx jest secret-notes.controller.spec --no-coverage 2>&1 | tail -10
```

Expected: PASS — all 5 tests green.

- [ ] **Step 5: Commit**

```bash
git add backend/src/secret-notes/secret-notes.controller.ts backend/src/secret-notes/secret-notes.controller.spec.ts
git commit -m "feat: add SecretNotesController with landing page, reveal, and destroyed states"
```

---

### Task 4: Module + App wiring

**Files:**
- Create: `backend/src/secret-notes/secret-notes.module.ts`
- Modify: `backend/src/app.module.ts`

- [ ] **Step 1: Create the module**

```typescript
// backend/src/secret-notes/secret-notes.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SecretNote } from './secret-note.entity';
import { SecretNotesService } from './secret-notes.service';
import { SecretNotesController } from './secret-notes.controller';

@Module({
  imports: [TypeOrmModule.forFeature([SecretNote])],
  providers: [SecretNotesService],
  controllers: [SecretNotesController],
})
export class SecretNotesModule {}
```

- [ ] **Step 2: Import module and register entity in app.module.ts**

`app.module.ts` uses an explicit `entities` array in `TypeOrmModule.forRootAsync` (line ~56) AND a module imports array. Both must be updated.

```typescript
// 1. Add import at top of app.module.ts:
import { SecretNote } from './secret-notes/secret-note.entity';
import { SecretNotesModule } from './secret-notes/secret-notes.module';

// 2. In TypeOrmModule.forRootAsync config, add SecretNote to the entities array:
entities: [User, Conversation, Message, FriendRequest, BlockedUser, FcmToken, KeyBundle, OneTimePreKey, SecretNote],

// 3. In the top-level imports array, add:
SecretNotesModule,
```

- [ ] **Step 2b: Add NODE_ENV to docker-compose.yml**

`synchronize: true` only activates when `NODE_ENV === 'development'` — without it the `secret_notes` table is never created. Open `docker-compose.yml` and add `NODE_ENV: development` to the backend `environment:` block (around line 21):

```yaml
  backend:
    environment:
      NODE_ENV: development   # ← add this line
      # ... existing env vars
```

- [ ] **Step 3: Restart backend and verify table is created**

```bash
docker-compose restart backend
sleep 5
docker-compose logs backend --tail=30
```

Expected: No TypeORM errors. Backend starts on port 3000. Look for no "relation secret_notes does not exist" errors.

- [ ] **Step 4: Smoke test the endpoints**

```bash
# Should return landing page HTML
curl http://localhost:3000/note/nonexistent | grep "no longer exists"

# Should return 401 (no JWT)
curl -X POST http://localhost:3000/notes -H "Content-Type: application/json" \
  -d '{"ciphertext":"test","expiresIn":7200}'
```

Expected: first returns HTML with "no longer exists", second returns 401.

- [ ] **Step 5: Commit**

```bash
git add backend/src/secret-notes/secret-notes.module.ts backend/src/app.module.ts
git commit -m "feat: register SecretNotesModule in app — table auto-created on restart"
```

---

## Chunk 3: Frontend — Crypto utility + Dialog widget

### Task 5: Add encrypt package

**Files:**
- Modify: `frontend/pubspec.yaml`

- [ ] **Step 1: Add encrypt dependency**

In `frontend/pubspec.yaml`, add under `dependencies:`:

```yaml
  encrypt: ^5.0.3
```

- [ ] **Step 2: Install**

```bash
cd frontend && flutter pub get 2>&1 | tail -5
```

Expected: `Resolving dependencies... Got dependencies!`

- [ ] **Step 3: Commit**

```bash
git add frontend/pubspec.yaml frontend/pubspec.lock
git commit -m "feat: add encrypt package for AES-GCM client-side encryption"
```

---

### Task 6: AntiQuantumNoteDialog widget

**Files:**
- Create: `frontend/lib/widgets/anti_quantum_note_dialog.dart`

- [ ] **Step 1: Write the widget test**

```dart
// frontend/test/widgets/anti_quantum_note_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/widgets/anti_quantum_note_dialog.dart';

void main() {
  testWidgets('shows title and TTL chips', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AntiQuantumNoteDialog(
          onSend: (_, __) async {},
        ),
      ),
    ));

    expect(find.text('Anti-Quantum Note'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);
    expect(find.text('6h'), findsOneWidget);
    expect(find.text('12h'), findsOneWidget);
    expect(find.text('Generate & Send'), findsOneWidget);
  });

  testWidgets('Generate & Send disabled when text is empty', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AntiQuantumNoteDialog(
          onSend: (_, __) async {},
        ),
      ),
    ));

    final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Generate & Send enabled when text is non-empty', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AntiQuantumNoteDialog(
          onSend: (_, __) async {},
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();

    final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('calls onSend with content and selected TTL', (tester) async {
    String? capturedContent;
    int? capturedTtl;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AntiQuantumNoteDialog(
          onSend: (content, ttl) async {
            capturedContent = content;
            capturedTtl = ttl;
          },
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'secret text');
    await tester.pump();

    // Tap 12h chip
    await tester.tap(find.text('12h'));
    await tester.pump();

    // Tap Generate & Send
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(capturedContent, 'secret text');
    expect(capturedTtl, 43200);
  });
}
```

- [ ] **Step 2: Run test — verify it fails**

```bash
cd frontend && flutter test test/widgets/anti_quantum_note_dialog_test.dart 2>&1 | tail -10
```

Expected: FAIL — file not found.

- [ ] **Step 3: Write the widget**

```dart
// frontend/lib/widgets/anti_quantum_note_dialog.dart
import 'package:flutter/material.dart';

class AntiQuantumNoteDialog extends StatefulWidget {
  final Future<void> Function(String content, int expiresInSeconds) onSend;

  const AntiQuantumNoteDialog({super.key, required this.onSend});

  @override
  State<AntiQuantumNoteDialog> createState() => _AntiQuantumNoteDialogState();
}

class _AntiQuantumNoteDialogState extends State<AntiQuantumNoteDialog> {
  final _controller = TextEditingController();
  int _selectedTtl = 21600; // 6h default
  bool _sending = false;

  static const _ttlOptions = [
    (label: '2h', seconds: 7200),
    (label: '6h', seconds: 21600),
    (label: '12h', seconds: 43200),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    if (_sending || _controller.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(_controller.text.trim(), _selectedTtl);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmpty = _controller.text.trim().isEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚛️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'Anti-Quantum Note',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                color: Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Write your secret message...',
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade700),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: _ttlOptions.map((opt) {
              final selected = _selectedTtl == opt.seconds;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedTtl = opt.seconds),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFC0392B) : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? const Color(0xFFC0392B) : Colors.grey.shade700,
                        ),
                      ),
                      child: Text(
                        opt.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (isEmpty || _sending) ? null : _handleSend,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC0392B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Generate & Send', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Encrypted client-side · Key never leaves your device',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test — verify it passes**

```bash
cd frontend && flutter test test/widgets/anti_quantum_note_dialog_test.dart 2>&1 | tail -10
```

Expected: PASS — all 4 tests green.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/widgets/anti_quantum_note_dialog.dart frontend/test/widgets/anti_quantum_note_dialog_test.dart
git commit -m "feat: add AntiQuantumNoteDialog widget with TTL selection"
```

---

## Chunk 4: Frontend — Crypto + sendNote + tile wiring

### Task 7: sendNote in ChatProvider (crypto + API + send message)

**Files:**
- Modify: `frontend/lib/providers/chat_provider.dart`
- Modify: `frontend/lib/services/api_service.dart`

- [ ] **Step 1: Add createSecretNote to ApiService**

In `frontend/lib/services/api_service.dart`, add this method alongside other API methods:

```dart
Future<String> createSecretNote(String token, String ciphertext, int expiresIn) async {
  final response = await _client.post(
    Uri.parse('$baseUrl/notes'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode({'ciphertext': ciphertext, 'expiresIn': expiresIn}),
  );
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception('Failed to create secret note: ${response.statusCode}');
  }
  final data = jsonDecode(response.body);
  return data['token'] as String;
}
```

- [ ] **Step 2: Add sendAntiQuantumNote to ChatProvider**

In `frontend/lib/providers/chat_provider.dart`, add this import at the top if not already present:

```dart
import 'package:encrypt/encrypt.dart' as enc;
```

`dart:convert` is already imported. Then add the method to the `ChatProvider` class:

```dart
Future<void> sendAntiQuantumNote({
  required String content,
  required int expiresInSeconds,
}) async {
  final token = _authToken;
  if (token == null) return;

  // 1. Generate AES-256 key + 96-bit IV locally
  final keyBytes = enc.Key.fromSecureRandom(32);
  final iv = enc.IV.fromSecureRandom(12);

  // 2. Encrypt with AES-GCM
  final encrypter = enc.Encrypter(enc.AES(keyBytes, mode: enc.AESMode.gcm));
  final encrypted = encrypter.encrypt(content, iv: iv);

  // 3. Encode: base64(iv):base64(ciphertext)
  final ciphertext = '${iv.base64}:${encrypted.base64}';

  // 4. POST /notes — receive note token
  final noteToken = await _apiService.createSecretNote(token, ciphertext, expiresInSeconds);

  // 5. Build URL with key in fragment (#)
  // AppConfig.baseUrl already points to the backend host (dev: http://host:3000,
  // prod: https://fireplace.ignorelist.com via --dart-define=BASE_URL=...).
  // The /note/:token route is served by the same NestJS backend.
  final keyBase64Url = base64Url.encode(keyBytes.bytes);
  final noteUrl = '${AppConfig.baseUrl}/note/$noteToken#$keyBase64Url';

  // 6. Send URL as plain text message in active conversation.
  // sendMessage() reads _activeConversationId and recipientId internally.
  sendMessage(noteUrl);
}
```

- [ ] **Step 3: Run existing ChatProvider tests to verify nothing broke**

```bash
cd frontend && flutter test 2>&1 | tail -15
```

Expected: all existing tests still pass.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/services/api_service.dart frontend/lib/providers/chat_provider.dart
git commit -m "feat: add sendAntiQuantumNote — AES-GCM encrypt + POST /notes + send URL as message"
```

---

### Task 8: Add tile to chat_action_tiles.dart

**Files:**
- Modify: `frontend/lib/widgets/chat_action_tiles.dart`

- [ ] **Step 1: Read the current tile list**

Open `frontend/lib/widgets/chat_action_tiles.dart` and find the list of `_ActionTile` widgets. Currently there are 6: Clear, Timer, Ping, Attachment, Draw, GIF.

- [ ] **Step 2: Add the AQ Note tile**

`_ActionTile` accepts `icon`, `tooltip`, `color` (required), `onTap` — no `label` prop. `iconColor` is already defined at the top of `build()` as `Theme.of(context).colorScheme.primary`. Add the tile after the GIF tile (last in the list):

```dart
_ActionTile(
  icon: Icons.science_outlined,
  tooltip: 'Anti-Quantum Note',
  color: iconColor,
  onTap: () => _showAntiQuantumNoteDialog(context),
),
```

- [ ] **Step 3: Add _showAntiQuantumNoteDialog method**

`ChatActionTiles` is a `StatelessWidget` with no `recipientId`/`conversationId` props — IDs are always obtained at tap-time from `ChatProvider` using `_requireActiveConversation(context)`, the same pattern used by `_sendPing` and `_pickAttachment`. `sendAntiQuantumNote` also reads the active conversation internally via `sendMessage`, so no IDs need to be passed.

Add this method alongside `_sendPing` in the file:

```dart
void _showAntiQuantumNoteDialog(BuildContext context) {
  final result = _requireActiveConversation(context);
  if (result == null) return; // shows snackbar if no active conversation

  final chat = context.read<ChatProvider>();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => AntiQuantumNoteDialog(
      onSend: (content, ttl) async {
        await chat.sendAntiQuantumNote(
          content: content,
          expiresInSeconds: ttl,
        );
        if (context.mounted) {
          Navigator.of(context).pop();
          showTopSnackBar(context, 'Anti-Quantum Note sent');
        }
      },
    ),
  );
}
```

Add the import at the top of the file:

```dart
import 'anti_quantum_note_dialog.dart';
```

- [ ] **Step 4: Verify _requireActiveConversation signature**

Confirm the method signature in the file is `(ConversationModel, int)? _requireActiveConversation(BuildContext context)`. It shows a snackbar and returns `null` if no conversation is active — the guard call at the top handles the case correctly.

- [ ] **Step 5: Run flutter analyze**

```bash
cd frontend && flutter analyze 2>&1 | grep -E "error|warning" | head -20
```

Expected: no new errors.

- [ ] **Step 6: Run all tests**

```bash
cd frontend && flutter test 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/widgets/chat_action_tiles.dart
git commit -m "feat: add Anti-Quantum Note tile to chat action panel"
```

---

## Final Smoke Test

- [ ] Start backend: `docker-compose up`
- [ ] Start frontend: `cd frontend && flutter run -d chrome`
- [ ] Open a chat → expand action tiles → tap ⚛️ AQ Note
- [ ] Type a message, select TTL (e.g. 6h), tap Generate & Send
- [ ] Verify a URL appears in chat as a sent message
- [ ] Open the URL in a new browser tab (incognito) — should see landing page with "Reveal & Destroy"
- [ ] Click Reveal & Destroy — should see the decrypted message
- [ ] Refresh the page — should see "This note no longer exists"
- [ ] Try opening the same URL again in a third tab — same destroyed page

- [ ] **Final commit (if any cleanup needed)**

```bash
cd backend && npx jest --no-coverage 2>&1 | tail -5
cd frontend && flutter test 2>&1 | tail -5
git add -A && git commit -m "feat: Anti-Quantum Note — complete implementation"
```
