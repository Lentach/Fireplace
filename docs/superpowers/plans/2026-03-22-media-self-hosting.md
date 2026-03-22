# Media Self-Hosting + AES-256-GCM Encryption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Cloudinary with self-hosted VM storage and add client-side AES-256-GCM encryption for all message media.

**Architecture:** Flutter encrypts media (AES-256-GCM, `compute()` isolate) before upload; encrypted blob stored on VM disk; key+IV packed inside the Signal E2E envelope. Nginx serves blobs via X-Accel-Redirect (Node.js never streams files). Avatars are unencrypted and publicly accessible (same as Signal/WhatsApp).

**Tech Stack:** NestJS 11, `@nestjs/schedule` (cron), `fs/promises` (Node built-in), Flutter 3.x, `pointycastle ^4.0.0` (AES-256-GCM), Dart `compute()`, `http` package `StreamedRequest` (progress), Nginx X-Accel-Redirect, Docker named volume.

**Spec:** `docs/superpowers/specs/2026-03-22-media-self-hosting-design.md`

---

## File Map

### Backend — create
| File | Responsibility |
|---|---|
| `backend/src/media/local-storage.service.ts` | Write/delete files on disk; same method signatures as CloudinaryService |
| `backend/src/media/local-storage.service.spec.ts` | Unit tests for LocalStorageService |
| `backend/src/media/media.controller.ts` | POST /media/upload (JWT), GET /media/msgs/:fn, GET /media/avatars/:fn (public) |
| `backend/src/media/media.controller.spec.ts` | Unit tests for MediaController |
| `backend/src/media/media-cleanup.service.ts` | On-demand delete + cron at 03:00 |
| `backend/src/media/media-cleanup.service.spec.ts` | Unit tests for MediaCleanupService |
| `backend/src/media/media.module.ts` | Global NestJS module exporting LocalStorageService + MediaCleanupService |

### Backend — modify
| File | Change |
|---|---|
| `backend/src/chat/dto/chat.dto.ts` | Replace `CLOUDINARY_URL_REGEX` with `MEDIA_URL_REGEX` (covers Cloudinary + self-hosted + raw/upload) |
| `backend/src/chat/dto/chat.dto.spec.ts` | Add test cases for new regex |
| `backend/src/app.module.ts` | Swap `CloudinaryModule` → `MediaModule` (`ScheduleModule.forRoot()` already present) |
| `backend/src/users/users.controller.ts` | Inject `LocalStorageService` instead of `CloudinaryService` |
| `backend/src/messages/messages.module.ts` | Remove `CloudinaryModule`; route removed in Task 5 |
| `backend/src/messages/messages.controller.ts` | Remove `POST /messages/upload-media` entirely |

### Backend — delete
| File | Reason |
|---|---|
| `backend/src/cloudinary/cloudinary.service.ts` | Replaced by LocalStorageService |
| `backend/src/cloudinary/cloudinary.module.ts` | Replaced by MediaModule |

### Infrastructure
| File | Change |
|---|---|
| `docker-compose.yml` | Add `media_storage` volume; add `MEDIA_BASE_URL` env; remove Cloudinary env vars |
| `frontend/nginx.conf` | Add `/internal/media/` internal block; add `/media/` proxy block; increase `client_max_body_size` to 11m |

### Frontend — create
| File | Responsibility |
|---|---|
| `frontend/lib/services/media_crypto_service.dart` | AES-256-GCM encrypt/decrypt in `compute()` isolate |
| `frontend/test/services/media_crypto_service_test.dart` | Unit tests for MediaCryptoService |

### Frontend — modify
| File | Change |
|---|---|
| `frontend/lib/utils/e2e_envelope.dart` | Add `mediaKey`/`mediaIv` fields to `build()` and `parse()` |
| `frontend/lib/services/api_service.dart` | Replace `uploadMedia` with `uploadEncryptedMedia` (hits `/media/upload`, sends binary blob with StreamedRequest + progress callback) |
| `frontend/lib/providers/messaging_provider.dart` | In all send methods: encrypt before upload, write `_pendingSendContent` with mediaKey/mediaIv, pass key+IV to `_encryptAndSend` |
| `frontend/lib/widgets/message/image_message_content.dart` | Decrypt blob before `MemoryImage` display |
| `frontend/lib/widgets/audio/playback_controller.dart` | Decrypt blob in `_loadAndPlayAudio()` before writing to audio cache |
| `frontend/lib/widgets/message/voice_message_content.dart` | No logic change — delegates to PlaybackController |
| `frontend/lib/widgets/message/gif_message_content.dart` | Decrypt blob; blob URL on web, `Image.memory` on native |
| `frontend/lib/widgets/message/file_message_content.dart` | Decrypt blob to temp file |

---

## ═══════════════════════════════════════
## PHASE 1: BACKEND
## ═══════════════════════════════════════

---

### Task 1: LocalStorageService

**Files:**
- Create: `backend/src/media/local-storage.service.ts`
- Create: `backend/src/media/local-storage.service.spec.ts`

- [ ] **Step 1: Write failing tests**

```typescript
// backend/src/media/local-storage.service.spec.ts
import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { LocalStorageService } from './local-storage.service';
import * as fs from 'fs/promises';
import * as path from 'path';

jest.mock('fs/promises');
const mockFs = fs as jest.Mocked<typeof fs>;

describe('LocalStorageService', () => {
  let service: LocalStorageService;

  beforeEach(async () => {
    mockFs.mkdir.mockResolvedValue(undefined);
    mockFs.writeFile.mockResolvedValue(undefined);
    mockFs.unlink.mockResolvedValue(undefined);

    const module = await Test.createTestingModule({
      providers: [
        LocalStorageService,
        {
          provide: ConfigService,
          useValue: {
            get: (key: string) => {
              if (key === 'MEDIA_BASE_URL') return 'https://example.com';
              if (key === 'MEDIA_DIR') return '/app/media';
            },
          },
        },
      ],
    }).compile();

    service = module.get(LocalStorageService);
  });

  it('uploadImage returns secureUrl with /media/msgs/ path', async () => {
    const result = await service.uploadImage(1, Buffer.from('data'), 'image/jpeg');
    expect(result.secureUrl).toMatch(/^https:\/\/example\.com\/media\/msgs\/.+\.bin$/);
    expect(mockFs.writeFile).toHaveBeenCalled();
  });

  it('uploadAvatar returns secureUrl with /media/avatars/ path and .jpg extension', async () => {
    const result = await service.uploadAvatar(1, Buffer.from('data'), 'image/jpeg');
    expect(result.secureUrl).toMatch(/^https:\/\/example\.com\/media\/avatars\/.+\.jpg$/);
  });

  it('uploadVoiceMessage returns provided duration', async () => {
    const result = await service.uploadVoiceMessage(1, Buffer.from('data'), 'audio/m4a', 42);
    expect(result.duration).toBe(42);
    expect(result.secureUrl).toMatch(/\.bin$/);
  });

  it('uploadRawFile returns secureUrl with .bin extension', async () => {
    const result = await service.uploadRawFile(1, Buffer.from('data'), 'application/pdf', 'doc.pdf');
    expect(result.secureUrl).toMatch(/\.bin$/);
  });

  it('deleteFile calls unlink with correct path', async () => {
    await service.deleteFile('msgs/abc123.bin');
    expect(mockFs.unlink).toHaveBeenCalledWith('/app/media/msgs/abc123.bin');
  });

  it('deleteFile is a no-op for Cloudinary URLs (skips)', async () => {
    await service.deleteFile('https://res.cloudinary.com/demo/image/upload/sample.jpg');
    expect(mockFs.unlink).not.toHaveBeenCalled();
  });


  it('deleteFile does not throw if file not found', async () => {
    const err = Object.assign(new Error(), { code: 'ENOENT' });
    mockFs.unlink.mockRejectedValueOnce(err);
    await expect(service.deleteFile('msgs/missing.bin')).resolves.not.toThrow();
  });
});
```

- [ ] **Step 2: Run tests — confirm FAIL**

```bash
cd backend && npx jest local-storage.service.spec.ts --no-coverage
```
Expected: `Cannot find module './local-storage.service'`

- [ ] **Step 3: Implement LocalStorageService**

```typescript
// backend/src/media/local-storage.service.ts
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as fs from 'fs/promises';
import * as path from 'path';
import { randomUUID } from 'crypto';

export interface UploadAvatarResult { secureUrl: string; publicId: string; }
export interface UploadImageResult { secureUrl: string; publicId: string; }
export interface UploadVoiceResult { secureUrl: string; publicId: string; duration: number; }
export interface UploadRawFileResult { secureUrl: string; publicId: string; }

@Injectable()
export class LocalStorageService {
  private readonly baseUrl: string;
  private readonly mediaDir: string;

  constructor(private configService: ConfigService) {
    this.baseUrl = configService.get<string>('MEDIA_BASE_URL', 'http://localhost:3000');
    this.mediaDir = configService.get<string>('MEDIA_DIR', '/app/media');
  }

  async uploadAvatar(userId: number, buffer: Buffer, mimeType: string): Promise<UploadAvatarResult> {
    const ext = mimeType.includes('png') ? 'png' : 'jpg';
    const filename = `${randomUUID()}.${ext}`;
    const publicId = `avatars/${filename}`;
    await fs.mkdir(path.join(this.mediaDir, 'avatars'), { recursive: true });
    await fs.writeFile(path.join(this.mediaDir, publicId), buffer, { mode: 0o644 });
    return { secureUrl: `${this.baseUrl}/media/${publicId}`, publicId };
  }

  async uploadImage(_userId: number, buffer: Buffer, _mimeType: string): Promise<UploadImageResult> {
    return this._saveMsgBlob(buffer);
  }

  async uploadVoiceMessage(_userId: number, buffer: Buffer, _mimeType: string, duration = 0, _expiresIn?: number): Promise<UploadVoiceResult> {
    const { secureUrl, publicId } = await this._saveMsgBlob(buffer);
    return { secureUrl, publicId, duration };
  }

  async uploadRawFile(_userId: number, buffer: Buffer, _mimeType: string, _filename?: string): Promise<UploadRawFileResult> {
    return this._saveMsgBlob(buffer);
  }

  async deleteAvatar(publicId: string): Promise<void> {
    await this.deleteFile(publicId);
  }

  /** publicId = relative path like 'msgs/abc.bin' or 'avatars/uuid.jpg'.
   *  Full Cloudinary URLs are skipped (legacy messages). ENOENT is silently ignored. */
  async deleteFile(publicId: string): Promise<void> {
    if (publicId.startsWith('http')) return; // skip legacy Cloudinary URLs
    try {
      await fs.unlink(path.join(this.mediaDir, publicId));
    } catch (err: any) {
      if (err?.code !== 'ENOENT') throw err;
    }
  }

  /** extractPublicId: strips baseUrl prefix to get relative path for deleteFile. */
  extractPublicId(mediaUrl: string): string {
    return mediaUrl.replace(`${this.baseUrl}/media/`, '');
  }

  private async _saveMsgBlob(buffer: Buffer): Promise<{ secureUrl: string; publicId: string }> {
    const filename = `${randomUUID()}.bin`;
    const publicId = `msgs/${filename}`;
    await fs.mkdir(path.join(this.mediaDir, 'msgs'), { recursive: true });
    await fs.writeFile(path.join(this.mediaDir, publicId), buffer, { mode: 0o644 });
    return { secureUrl: `${this.baseUrl}/media/${publicId}`, publicId };
  }
}
```

- [ ] **Step 4: Run tests — confirm PASS**

```bash
cd backend && npx jest local-storage.service.spec.ts --no-coverage
```
Expected: all 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add backend/src/media/local-storage.service.ts backend/src/media/local-storage.service.spec.ts
git commit -m "feat(media): add LocalStorageService replacing Cloudinary for media storage"
```

---

### Task 2: MediaController

**Files:**
- Create: `backend/src/media/media.controller.ts`
- Create: `backend/src/media/media.controller.spec.ts`

- [ ] **Step 1: Write failing tests**

```typescript
// backend/src/media/media.controller.spec.ts
import { Test } from '@nestjs/testing';
import { MediaController } from './media.controller';
import { LocalStorageService } from './local-storage.service';
import { ThrottlerModule } from '@nestjs/throttler';
import { BadRequestException } from '@nestjs/common';

const mockStorage = {
  uploadImage: jest.fn().mockResolvedValue({ secureUrl: 'https://example.com/media/msgs/abc.bin', publicId: 'msgs/abc.bin' }),
  uploadVoiceMessage: jest.fn().mockResolvedValue({ secureUrl: 'https://example.com/media/msgs/abc.bin', publicId: 'msgs/abc.bin', duration: 5 }),
  uploadRawFile: jest.fn().mockResolvedValue({ secureUrl: 'https://example.com/media/msgs/abc.bin', publicId: 'msgs/abc.bin' }),
  uploadAvatar: jest.fn().mockResolvedValue({ secureUrl: 'https://example.com/media/avatars/abc.jpg', publicId: 'avatars/abc.jpg' }),
};

const fakeFile = (size = 100, mime = 'application/octet-stream') =>
  ({ buffer: Buffer.alloc(size), mimetype: mime, size, originalname: 'test.bin' } as any);

const fakeReq = { user: { id: 1 } } as any;
const fakeRes = {
  setHeader: jest.fn(),
  status: jest.fn().mockReturnThis(),
  send: jest.fn(),
} as any;

describe('MediaController', () => {
  let controller: MediaController;

  beforeEach(async () => {
    jest.clearAllMocks();
    const module = await Test.createTestingModule({
      imports: [ThrottlerModule.forRoot([{ ttl: 60000, limit: 100 }])],
      controllers: [MediaController],
      providers: [{ provide: LocalStorageService, useValue: mockStorage }],
    }).compile();
    controller = module.get(MediaController);
  });

  it('upload image returns mediaUrl', async () => {
    const result = await controller.upload(fakeFile(), { mediaType: 'image' } as any, fakeReq);
    expect(result).toEqual({ mediaUrl: 'https://example.com/media/msgs/abc.bin' });
    expect(mockStorage.uploadImage).toHaveBeenCalledWith(1, expect.any(Buffer), 'application/octet-stream');
  });

  it('upload voice returns mediaUrl + mediaDuration', async () => {
    const result = await controller.upload(fakeFile(), { mediaType: 'voice', duration: 5 } as any, fakeReq);
    expect(result).toMatchObject({ mediaUrl: expect.any(String), mediaDuration: 5 });
  });

  it('upload without file throws BadRequestException', async () => {
    await expect(controller.upload(undefined as any, { mediaType: 'image' } as any, fakeReq))
      .rejects.toThrow(BadRequestException);
  });

  it('serveMsgs sets X-Accel-Redirect header', async () => {
    await controller.serveMsgs('abc.bin', fakeRes);
    expect(fakeRes.setHeader).toHaveBeenCalledWith('X-Accel-Redirect', '/internal/media/msgs/abc.bin');
  });

  it('serveAvatars sets X-Accel-Redirect header', async () => {
    await controller.serveAvatars('uuid.jpg', fakeRes);
    expect(fakeRes.setHeader).toHaveBeenCalledWith('X-Accel-Redirect', '/internal/media/avatars/uuid.jpg');
  });
});
```

- [ ] **Step 2: Run tests — confirm FAIL**

```bash
cd backend && npx jest media.controller.spec.ts --no-coverage
```
Expected: `Cannot find module './media.controller'`

- [ ] **Step 3: Create upload DTO + implement MediaController**

First create a DTO:
```typescript
// backend/src/media/dto/upload-media.dto.ts
import { IsIn, IsNumber, IsOptional, IsString } from 'class-validator';
import { Type } from 'class-transformer';

export class UploadMediaDto {
  @IsIn(['image', 'voice', 'gif', 'file', 'avatar'])
  mediaType: 'image' | 'voice' | 'gif' | 'file' | 'avatar';

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  duration?: number;

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  expiresIn?: number;

  @IsOptional()
  @IsString()
  fileName?: string;
}
```

Then the controller:
```typescript
// backend/src/media/media.controller.ts
import {
  Controller, Post, Get, UseGuards, UseInterceptors,
  UploadedFile, Body, Request, Res, Param, BadRequestException,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Throttle } from '@nestjs/throttler';
import { Response } from 'express';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { LocalStorageService } from './local-storage.service';
import { UploadMediaDto } from './dto/upload-media.dto';
import { validateDto } from '../chat/utils/dto.validator';

@Controller('media')
export class MediaController {
  constructor(private storage: LocalStorageService) {}

  @Post('upload')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 20, ttl: 60000 } })
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: 11 * 1024 * 1024 } }))
  async upload(
    @UploadedFile() file: Express.Multer.File,
    @Body() body: Record<string, unknown>,
    @Request() req: any,
  ) {
    if (!file) throw new BadRequestException('No file uploaded');
    const dto = validateDto(UploadMediaDto, body);
    const userId = req.user.id;

    if (dto.mediaType === 'voice') {
      const result = await this.storage.uploadVoiceMessage(userId, file.buffer, file.mimetype, dto.duration ?? 0, dto.expiresIn);
      return { mediaUrl: result.secureUrl, mediaDuration: result.duration };
    }
    if (dto.mediaType === 'file') {
      const result = await this.storage.uploadRawFile(userId, file.buffer, file.mimetype, dto.fileName ?? file.originalname);
      return { mediaUrl: result.secureUrl, fileName: dto.fileName ?? file.originalname };
    }
    if (dto.mediaType === 'avatar') {
      const result = await this.storage.uploadAvatar(userId, file.buffer, file.mimetype);
      return { mediaUrl: result.secureUrl };
    }
    // image or gif
    const result = await this.storage.uploadImage(userId, file.buffer, file.mimetype);
    return { mediaUrl: result.secureUrl };
  }

  // More specific path BEFORE generic :filename — avatars segment is literal, no collision risk
  @Get('avatars/:filename')
  @Throttle({ default: { limit: 60, ttl: 60000 } })
  async serveAvatars(@Param('filename') filename: string, @Res() res: Response) {
    res.setHeader('X-Accel-Redirect', `/internal/media/avatars/${filename}`);
    res.status(200).send();
  }

  @Get('msgs/:filename')
  @Throttle({ default: { limit: 60, ttl: 60000 } })
  async serveMsgs(@Param('filename') filename: string, @Res() res: Response) {
    res.setHeader('X-Accel-Redirect', `/internal/media/msgs/${filename}`);
    res.status(200).send();
  }
}
```

- [ ] **Step 4: Run tests — confirm PASS**

```bash
cd backend && npx jest media.controller.spec.ts --no-coverage
```
Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add backend/src/media/media.controller.ts backend/src/media/media.controller.spec.ts backend/src/media/dto/upload-media.dto.ts
git commit -m "feat(media): add MediaController with upload + X-Accel-Redirect serve endpoints"
```

---

### Task 3: MediaCleanupService

**Files:**
- Create: `backend/src/media/media-cleanup.service.ts`
- Create: `backend/src/media/media-cleanup.service.spec.ts`

- [ ] **Step 1: Write failing tests**

```typescript
// backend/src/media/media-cleanup.service.spec.ts
import { Test } from '@nestjs/testing';
import { MediaCleanupService } from './media-cleanup.service';
import { LocalStorageService } from './local-storage.service';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Message } from '../messages/message.entity';

const mockStorage = { deleteFile: jest.fn().mockResolvedValue(undefined), extractPublicId: jest.fn((url: string) => url.replace('https://example.com/media/', '')) };
const mockMessageRepo = { createQueryBuilder: jest.fn() };

describe('MediaCleanupService', () => {
  let service: MediaCleanupService;

  beforeEach(async () => {
    jest.clearAllMocks();
    const module = await Test.createTestingModule({
      providers: [
        MediaCleanupService,
        { provide: LocalStorageService, useValue: mockStorage },
        { provide: getRepositoryToken(Message), useValue: mockMessageRepo },
        { provide: 'MEDIA_BASE_URL', useValue: 'https://example.com' },
        { provide: 'MEDIA_DIR', useValue: '/app/media' },  // required by cron cleanup
      ],
    }).compile();
    service = module.get(MediaCleanupService);
  });

  it('deleteMediaFile skips null mediaUrl', async () => {
    await service.deleteMediaFile(null);
    expect(mockStorage.deleteFile).not.toHaveBeenCalled();
  });

  it('deleteMediaFile skips Cloudinary URLs', async () => {
    await service.deleteMediaFile('https://res.cloudinary.com/demo/image/upload/sample.jpg');
    expect(mockStorage.deleteFile).not.toHaveBeenCalled();
  });

  it('deleteMediaFile calls deleteFile with publicId for self-hosted URLs', async () => {
    await service.deleteMediaFile('https://example.com/media/msgs/abc.bin');
    expect(mockStorage.extractPublicId).toHaveBeenCalledWith('https://example.com/media/msgs/abc.bin');
    expect(mockStorage.deleteFile).toHaveBeenCalledWith('msgs/abc.bin');
  });

  it('deleteMediaFile does not throw on storage error', async () => {
    mockStorage.deleteFile.mockRejectedValueOnce(new Error('disk error'));
    await expect(service.deleteMediaFile('https://example.com/media/msgs/abc.bin')).resolves.not.toThrow();
  });
});
```

- [ ] **Step 2: Run tests — confirm FAIL**

```bash
cd backend && npx jest media-cleanup.service.spec.ts --no-coverage
```
Expected: `Cannot find module './media-cleanup.service'`

- [ ] **Step 3: Implement MediaCleanupService**

```typescript
// backend/src/media/media-cleanup.service.ts
import { Injectable, Logger, Inject } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as fs from 'fs/promises';
import * as path from 'path';
import { LocalStorageService } from './local-storage.service';
import { Message } from '../messages/message.entity';

@Injectable()
export class MediaCleanupService {
  private readonly logger = new Logger(MediaCleanupService.name);

  constructor(
    private storage: LocalStorageService,
    @InjectRepository(Message) private messageRepo: Repository<Message>,
    @Inject('MEDIA_BASE_URL') private mediaBaseUrl: string,
    @Inject('MEDIA_DIR') private mediaDir: string,
  ) {}

  /** Delete a single media file by its URL. No-op for null or Cloudinary URLs. */
  async deleteMediaFile(mediaUrl: string | null | undefined): Promise<void> {
    if (!mediaUrl) return;
    if (!mediaUrl.startsWith(this.mediaBaseUrl)) return; // skip Cloudinary legacy
    try {
      const publicId = this.storage.extractPublicId(mediaUrl);
      await this.storage.deleteFile(publicId);
    } catch (err) {
      this.logger.warn(`Failed to delete media file ${mediaUrl}: ${err}`);
    }
  }

  /** Cron: daily at 03:00 — delete orphaned and expired files from disk. */
  @Cron('0 3 * * *')
  async cleanupOrphanedFiles(): Promise<void> {
    this.logger.log('Starting media cleanup cron');
    const msgsDir = path.join(this.mediaDir, 'msgs');

    let diskFiles: string[];
    try {
      diskFiles = await fs.readdir(msgsDir);
    } catch {
      this.logger.warn('Media msgs dir not found — skipping cleanup');
      return;
    }

    // Fetch all currently valid self-hosted media URLs from DB
    const validRows: { mediaUrl: string }[] = await this.messageRepo
      .createQueryBuilder('msg')
      .select('msg.mediaUrl', 'mediaUrl')
      .where('msg.mediaUrl IS NOT NULL')
      .andWhere('msg.mediaUrl LIKE :prefix', { prefix: `${this.mediaBaseUrl}/media/%` })
      .andWhere('(msg.expiresAt IS NULL OR msg.expiresAt > NOW())')
      .getRawMany();

    const validFilenames = new Set(
      validRows.map(r => r.mediaUrl.split('/').pop()),
    );

    let deleted = 0;
    for (const file of diskFiles) {
      if (!validFilenames.has(file)) {
        try {
          await fs.unlink(path.join(msgsDir, file));
          deleted++;
        } catch (err) {
          this.logger.warn(`Cron: failed to delete ${file}: ${err}`);
        }
      }
    }
    this.logger.log(`Cron cleanup done: ${deleted} files deleted`);
  }
}
```

- [ ] **Step 4: Run tests — confirm PASS**

```bash
cd backend && npx jest media-cleanup.service.spec.ts --no-coverage
```
Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add backend/src/media/media-cleanup.service.ts backend/src/media/media-cleanup.service.spec.ts
git commit -m "feat(media): add MediaCleanupService with on-demand delete + cron orphan cleanup"
```

---

### Task 4: MediaModule + CLOUDINARY_URL_REGEX fix

**Files:**
- Create: `backend/src/media/media.module.ts`
- Modify: `backend/src/chat/dto/chat.dto.ts`
- Modify: `backend/src/chat/dto/chat.dto.spec.ts`
- Modify: `backend/src/chat/utils/dto.validator.spec.ts`

- [ ] **Step 1: Update regex test cases**

Open `backend/src/chat/dto/chat.dto.spec.ts`. Find the test(s) for `mediaUrl` validation and add:

```typescript
// In the SendMessageDto describe block, add these cases:
it('accepts self-hosted media URL', () => {
  const dto = new SendMessageDto();
  dto.mediaUrl = `${process.env.MEDIA_BASE_URL ?? 'http://localhost:3000'}/media/msgs/abc.bin`;
  // validate — should pass
});

it('accepts Cloudinary raw/upload URL (FILE type backward compat)', () => {
  const dto = new SendMessageDto();
  dto.mediaUrl = 'https://res.cloudinary.com/demo/raw/upload/sample.pdf';
  // validate — should pass
});

it('rejects arbitrary URLs', () => {
  const dto = new SendMessageDto();
  dto.mediaUrl = 'https://evil.com/file.bin';
  // validate — should fail
});
```

Run: `cd backend && npx jest chat.dto.spec.ts --no-coverage` — note which pass/fail before the fix.

- [ ] **Step 1b: Update dto.validator.spec.ts**

Open `backend/src/chat/utils/dto.validator.spec.ts`. Find any test that asserts `raw/upload` Cloudinary URLs are **rejected** and update it to **accept** them (they are now valid for FILE backward compat). Add a test case for self-hosted URLs being accepted.

Run: `cd backend && npx jest dto.validator.spec.ts --no-coverage` — note current state.

- [ ] **Step 2: Fix CLOUDINARY_URL_REGEX in chat.dto.ts**

In `backend/src/chat/dto/chat.dto.ts`, replace lines 14–15:

```typescript
// OLD:
const CLOUDINARY_URL_REGEX = /^https:\/\/res\.cloudinary\.com\/[a-zA-Z0-9_-]+\/(video|image)\/upload\/.+/;

// NEW — covers image/video/raw Cloudinary paths + self-hosted; env read at module load:
// Default to localhost:3000 so tests work without MEDIA_BASE_URL env var set
const _selfHostedOrigin = (process.env.MEDIA_BASE_URL ?? 'http://localhost:3000')
  .replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const MEDIA_URL_REGEX = new RegExp(
  `^https://(res\\.cloudinary\\.com/[a-zA-Z0-9_-]+/(video|image|raw)/upload/.+|${_selfHostedOrigin}/media/.+)`,
);
```

Also update the `@Matches` decorator on `mediaUrl`:
```typescript
@Matches(MEDIA_URL_REGEX, {
  message: 'mediaUrl must be a valid Cloudinary or self-hosted media URL',
})
```

**Note on local dev:** The regex matches `http://localhost:3000/media/...` but requires `https://` for the Cloudinary branch. Since all E2E messages send `encryptedContent` only (server never sees `mediaUrl` in the DTO), this regex fires only for legacy/non-E2E paths. No action needed for local dev.

- [ ] **Step 3: Create MediaModule**

```typescript
// backend/src/media/media.module.ts
import { Global, Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MulterModule } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { LocalStorageService } from './local-storage.service';
import { MediaController } from './media.controller';
import { MediaCleanupService } from './media-cleanup.service';
import { Message } from '../messages/message.entity';

@Global()
@Module({
  imports: [
    ConfigModule,
    TypeOrmModule.forFeature([Message]),
    MulterModule.register({ storage: memoryStorage() }),
  ],
  controllers: [MediaController],
  providers: [
    LocalStorageService,
    MediaCleanupService,
    {
      provide: 'MEDIA_BASE_URL',
      inject: [ConfigService],
      useFactory: (cfg: ConfigService) => cfg.get('MEDIA_BASE_URL', 'http://localhost:3000'),
    },
    {
      provide: 'MEDIA_DIR',
      inject: [ConfigService],
      useFactory: (cfg: ConfigService) => cfg.get('MEDIA_DIR', '/app/media'),
    },
  ],
  exports: [LocalStorageService, MediaCleanupService],
})
export class MediaModule {}
```

- [ ] **Step 4: Run all backend tests — confirm PASS**

```bash
cd backend && npm test
```
Expected: 184+ tests pass (existing suite unaffected + new tests).

- [ ] **Step 5: Commit**

```bash
git add backend/src/media/media.module.ts backend/src/chat/dto/chat.dto.ts \
        backend/src/chat/dto/chat.dto.spec.ts backend/src/chat/utils/dto.validator.spec.ts
git commit -m "feat(media): add MediaModule; fix mediaUrl regex to cover raw/upload + self-hosted URLs"
```

---

### Task 5: Wire MediaModule + remove Cloudinary

**Files:**
- Modify: `backend/src/app.module.ts`
- Modify: `backend/src/users/users.controller.ts`
- Modify: `backend/src/messages/messages.module.ts`
- Modify: `backend/src/messages/messages.controller.ts`
- Delete: `backend/src/cloudinary/cloudinary.service.ts`
- Delete: `backend/src/cloudinary/cloudinary.module.ts`

- [ ] **Step 1: Update app.module.ts**

In `backend/src/app.module.ts`:
1. Remove: `import { CloudinaryModule } from './cloudinary/cloudinary.module';`
2. Add: `import { MediaModule } from './media/media.module';`
3. In `imports[]`: replace `CloudinaryModule` with `MediaModule`
4. **Note:** `ScheduleModule.forRoot()` is already present in `app.module.ts` — do not add it again.

- [ ] **Step 2: Update users.controller.ts**

In `backend/src/users/users.controller.ts`:
1. Replace: `import { CloudinaryService } from '../cloudinary/cloudinary.service';`
   With: `import { LocalStorageService } from '../media/local-storage.service';`
2. Replace constructor injection: `private cloudinaryService: CloudinaryService`
   With: `private storageService: LocalStorageService`
3. In `uploadProfilePicture`: replace `this.cloudinaryService.uploadAvatar(...)` with `this.storageService.uploadAvatar(...)`
4. In `deleteProfilePicture` (if exists): replace `this.cloudinaryService.deleteAvatar(...)` with `this.storageService.deleteAvatar(...)`

- [ ] **Step 3: Remove /messages/upload-media + CloudinaryModule from messages**

In `backend/src/messages/messages.module.ts`:
- Remove `CloudinaryModule` from imports array
- Remove its import statement

In `backend/src/messages/messages.controller.ts`:
- Remove the entire `@Post('upload-media')` method and its decorators
- Remove `CloudinaryService` from constructor and import

- [ ] **Step 4: Delete Cloudinary files + uninstall npm package**

```bash
rm backend/src/cloudinary/cloudinary.service.ts
rm backend/src/cloudinary/cloudinary.module.ts
rmdir backend/src/cloudinary 2>/dev/null || true
cd backend && npm uninstall cloudinary
```

Also remove `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` from any `.env.example` or README docs if present.

- [ ] **Step 5: Run full backend test suite**

```bash
cd backend && npm test
```
Expected: all tests pass. If any test imports `CloudinaryService`, update it to use `LocalStorageService`.

- [ ] **Step 6: Start backend + smoke test upload endpoint**

```bash
docker-compose up
```
In another terminal:
```bash
curl -X POST http://localhost:3000/media/upload \
  -H "Authorization: Bearer <your_jwt>" \
  -F "file=@/tmp/test.jpg" \
  -F "mediaType=image"
```
Expected: `{"mediaUrl":"http://localhost:3000/media/msgs/...bin"}`

- [ ] **Step 7: Commit**

```bash
git add backend/src/app.module.ts backend/src/users/users.controller.ts \
        backend/src/messages/messages.module.ts backend/src/messages/messages.controller.ts
git commit -m "feat(media): wire MediaModule, remove CloudinaryModule, replace /messages/upload-media"
```

---

---

### Task 5b: Wire on-demand cleanup to chat events

**Files:**
- Modify: `backend/src/chat/services/chat-message.service.ts`
- Modify: `backend/src/chat/services/chat-conversation.service.ts`
- Modify: `backend/src/users/users.service.ts`

`MediaCleanupService.deleteMediaFile` must be called before rows are deleted — otherwise the `mediaUrl` is gone from DB before the file can be looked up.

- [ ] **Step 1: Inject MediaCleanupService into chat-message.service.ts**

In `chat-message.service.ts` constructor, add `MediaCleanupService` injection. Then in `handleDeleteMessage` (mode `for_everyone`) and `handleClearChatHistory`, call `deleteMediaFile` on affected messages **before** deleting rows:

```typescript
// deleteMessage for_everyone:
const msg = await this.messagesService.findById(messageId);
if (msg?.mediaUrl) await this.mediaCleanup.deleteMediaFile(msg.mediaUrl);
// then delete the message row

// clearChatHistory:
const messages = await this.messagesService.findByConversation(conversationId, senderId);
await Promise.all(
  messages
    .filter(m => m.mediaUrl)
    .map(m => this.mediaCleanup.deleteMediaFile(m.mediaUrl!))
);
// then clear history
```

- [ ] **Step 2: Wire deleteMediaFile in chat-conversation.service.ts**

In `handleDeleteConversationOnly` and `handleUnfriend`, delete media files before deleting the conversation:

```typescript
// Before deleting conversation:
const messages = await this.messagesService.findByConversation(conversationId);
await Promise.all(
  messages.filter(m => m.mediaUrl).map(m => this.mediaCleanup.deleteMediaFile(m.mediaUrl!))
);
```

- [ ] **Step 3: Wire deleteMediaFile in users.service.ts (deleteAccount)**

In `deleteAccount`, before deleting user messages, collect and delete all media files:

```typescript
const userMessages = await this.messagesService.findAllBySender(userId);
await Promise.all(
  userMessages.filter(m => m.mediaUrl).map(m => this.mediaCleanup.deleteMediaFile(m.mediaUrl!))
);
// then proceed with existing cascade deletion
```

- [ ] **Step 4: Run full backend test suite**

```bash
cd backend && npm test
```
Expected: all tests pass. The cron still acts as safety net — on-demand is a best-effort addition.

- [ ] **Step 5: Commit**

```bash
git add backend/src/chat/services/chat-message.service.ts \
        backend/src/chat/services/chat-conversation.service.ts \
        backend/src/users/users.service.ts
git commit -m "feat(media): wire MediaCleanupService.deleteMediaFile to deleteMessage, clearHistory, unfriend, deleteAccount"
```

---

### Task 6: Docker + Nginx

**Files:**
- Modify: `docker-compose.yml`
- Modify: `frontend/nginx.conf`

- [ ] **Step 1: Update docker-compose.yml**

```yaml
# docker-compose.yml — replace Cloudinary env vars with MEDIA_BASE_URL; add volume

services:
  db:
    # (unchanged)

  backend:
    image: node:20-alpine
    working_dir: /app
    ports:
      - '3000:3000'
    environment:
      DB_HOST: db
      DB_PORT: '5432'
      DB_USER: ${DB_USER:-postgres}
      DB_PASS: ${DB_PASS:-postgres}
      DB_NAME: ${DB_NAME:-chatdb}
      JWT_SECRET: ${JWT_SECRET:-my-super-secret-jwt-key-change-in-production}
      ALLOWED_ORIGINS: ${ALLOWED_ORIGINS:-http://localhost:3000}
      MEDIA_BASE_URL: ${MEDIA_BASE_URL:-http://localhost:3000}
      MEDIA_DIR: /app/media
      FIREBASE_SERVICE_ACCOUNT: ${FIREBASE_SERVICE_ACCOUNT}
      NODE_ENV: development
    depends_on:
      - db
    volumes:
      - ./backend:/app
      - media_storage:/app/media    # ADD THIS
    command: sh -c "npm install && npm run start:dev"

volumes:
  pgdata:
  media_storage:    # ADD THIS
```

- [ ] **Step 2: Update nginx.conf**

Replace entire `frontend/nginx.conf` with:

```nginx
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    client_max_body_size 11m;

    # Internal location — ONLY reachable via X-Accel-Redirect from NestJS
    location /internal/media/ {
        internal;
        alias /app/media/;
    }

    # Media upload — JWT checked in NestJS
    location = /media/upload {
        proxy_pass http://backend:3000;
        proxy_set_header Authorization $http_authorization;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Media serve — NestJS sets X-Accel-Redirect, Nginx serves from disk
    location /media/ {
        proxy_pass http://backend:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /auth/ {
        proxy_pass http://backend:3000/auth/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /users/ {
        proxy_pass http://backend:3000/users/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Authorization $http_authorization;
    }

    location /socket.io/ {
        proxy_pass http://backend:3000/socket.io/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

**Note for production deploy:** The production Nginx on the VM also needs a volume mount `media_storage:/app/media:ro` so `alias /app/media/` resolves correctly. Update the production `docker-compose.prod.yml` (or equivalent) with the same volume.

- [ ] **Step 3: Restart and verify the upload endpoint + X-Accel-Redirect header**

```bash
docker-compose down && docker-compose up
```
Upload a file and verify NestJS sets the correct header (dev compose has no Nginx — full X-Accel-Redirect file serving is only verified on production):
```bash
# Upload
curl -X POST http://localhost:3000/media/upload \
  -H "Authorization: Bearer <jwt>" \
  -F "file=@/tmp/test.jpg" -F "mediaType=image"
# → {"mediaUrl":"http://localhost:3000/media/msgs/<uuid>.bin"}

# Verify X-Accel-Redirect header is set (file won't actually be served without Nginx)
curl -I http://localhost:3000/media/msgs/<uuid>.bin
# → X-Accel-Redirect: /internal/media/msgs/<uuid>.bin
```
Full end-to-end (Nginx actually serving from disk) is verified after production deploy via `~/deploy.sh`.

- [ ] **Step 4: Commit**

```bash
git add docker-compose.yml frontend/nginx.conf
git commit -m "feat(infra): add media_storage volume + Nginx X-Accel-Redirect for self-hosted media"
```

---

## ═══════════════════════════════════════
## PHASE 2: FRONTEND
## ═══════════════════════════════════════

> **Prerequisite:** Phase 1 (backend) must be deployed and `/media/upload` endpoint working before starting Phase 2.

---

### Task 7: MediaCryptoService

**Files:**
- Create: `frontend/lib/services/media_crypto_service.dart`
- Create: `frontend/test/services/media_crypto_service_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// frontend/test/services/media_crypto_service_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/media_crypto_service.dart';

void main() {
  final service = MediaCryptoService();

  group('MediaCryptoService', () {
    test('encrypt produces ciphertext different from input', () async {
      final input = Uint8List.fromList(List.generate(100, (i) => i));
      final result = await service.encrypt(input);
      expect(result.ciphertext, isNot(equals(input)));
      expect(result.keyBase64.isNotEmpty, isTrue);
      expect(result.ivBase64.isNotEmpty, isTrue);
    });

    test('decrypt restores original bytes', () async {
      final input = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final encrypted = await service.encrypt(input);
      final decrypted = await service.decrypt(
        encrypted.ciphertext, encrypted.keyBase64, encrypted.ivBase64,
      );
      expect(decrypted, equals(input));
    });

    test('each encrypt call produces unique key and IV', () async {
      final input = Uint8List.fromList([42, 43, 44]);
      final a = await service.encrypt(input);
      final b = await service.encrypt(input);
      expect(a.keyBase64, isNot(equals(b.keyBase64)));
      expect(a.ivBase64, isNot(equals(b.ivBase64)));
    });

    test('decrypt with wrong key throws', () async {
      final input = Uint8List.fromList([1, 2, 3]);
      final encrypted = await service.encrypt(input);
      final other = await service.encrypt(input);
      expect(
        () => service.decrypt(encrypted.ciphertext, other.keyBase64, encrypted.ivBase64),
        throwsA(anything),
      );
    });

    test('throws ArgumentError for input over 20MB', () async {
      final huge = Uint8List(21 * 1024 * 1024);
      expect(() => service.encrypt(huge), throwsArgumentError);
    });
  });
}
```

- [ ] **Step 2: Run tests — confirm FAIL**

```bash
cd frontend && flutter test test/services/media_crypto_service_test.dart
```
Expected: `Target of URI hasn't been created: 'package:fireplace/services/media_crypto_service.dart'`

- [ ] **Step 3: Implement MediaCryptoService**

```dart
// frontend/lib/services/media_crypto_service.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

class EncryptedMedia {
  final Uint8List ciphertext; // AES-256-GCM output: encrypted bytes + 16-byte auth tag
  final String keyBase64;    // 32-byte key, base64-encoded
  final String ivBase64;     // 12-byte IV, base64-encoded
  const EncryptedMedia({required this.ciphertext, required this.keyBase64, required this.ivBase64});
}

class MediaCryptoService {
  static const int _maxBytes = 20 * 1024 * 1024;

  Future<EncryptedMedia> encrypt(Uint8List bytes) async {
    if (bytes.length > _maxBytes) throw ArgumentError('File exceeds 20MB limit');
    return compute(_encryptIsolate, bytes);
  }

  Future<Uint8List> decrypt(Uint8List ciphertext, String keyB64, String ivB64) {
    return compute(_decryptIsolate, _DecryptArgs(ciphertext, keyB64, ivB64));
  }
}

// Top-level functions required by compute()

EncryptedMedia _encryptIsolate(Uint8List plaintext) {
  final key = _randomBytes(32);
  final iv = _randomBytes(12);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
  final ciphertext = cipher.process(plaintext);
  return EncryptedMedia(
    ciphertext: ciphertext,
    keyBase64: base64.encode(key),
    ivBase64: base64.encode(iv),
  );
}

Uint8List _decryptIsolate(_DecryptArgs args) {
  final key = base64.decode(args.keyB64);
  final iv = base64.decode(args.ivB64);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
  return cipher.process(args.ciphertext);
}

Uint8List _randomBytes(int length) {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
}

class _DecryptArgs {
  final Uint8List ciphertext;
  final String keyB64;
  final String ivB64;
  const _DecryptArgs(this.ciphertext, this.keyB64, this.ivB64);
}
```

- [ ] **Step 4: Run tests — confirm PASS**

```bash
cd frontend && flutter test test/services/media_crypto_service_test.dart
```
Expected: all 5 tests pass.

- [ ] **Step 5: Run analyzer**

```bash
cd frontend && flutter analyze
```
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/services/media_crypto_service.dart frontend/test/services/media_crypto_service_test.dart
git commit -m "feat(frontend): add MediaCryptoService with AES-256-GCM encrypt/decrypt in compute() isolate"
```

---

### Task 8: E2eEnvelope + ApiService

**Files:**
- Modify: `frontend/lib/utils/e2e_envelope.dart`
- Modify: `frontend/lib/services/api_service.dart`

- [ ] **Step 1: Add E2eEnvelope tests (in existing test file if any, else new)**

Find or create `frontend/test/utils/e2e_envelope_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/utils/e2e_envelope.dart';

void main() {
  group('E2eEnvelope', () {
    test('build includes mediaKey and mediaIv when provided', () {
      final map = E2eEnvelope.build('hello', mediaKey: 'key123', mediaIv: 'iv456');
      expect(map['mediaKey'], 'key123');
      expect(map['mediaIv'], 'iv456');
    });

    test('build omits mediaKey/mediaIv when null', () {
      final map = E2eEnvelope.build('hello');
      expect(map.containsKey('mediaKey'), isFalse);
      expect(map.containsKey('mediaIv'), isFalse);
    });

    test('parse returns mediaKey and mediaIv from JSON', () {
      final json = jsonEncode({'content': 'hi', 'mediaKey': 'k', 'mediaIv': 'iv'});
      final result = E2eEnvelope.parse(json);
      expect(result.mediaKey, 'k');
      expect(result.mediaIv, 'iv');
    });

    test('parse returns null mediaKey for legacy envelope without mediaKey', () {
      final json = jsonEncode({'content': 'legacy', 'mediaUrl': 'https://res.cloudinary.com/...'});
      final result = E2eEnvelope.parse(json);
      expect(result.mediaKey, isNull);
      expect(result.mediaIv, isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests — confirm FAIL**

```bash
cd frontend && flutter test test/utils/e2e_envelope_test.dart
```
Expected: errors because `mediaKey`/`mediaIv` don't exist yet.

- [ ] **Step 3: Update e2e_envelope.dart**

In `frontend/lib/utils/e2e_envelope.dart`, make these changes:

```dart
// Add two new key constants:
static const String _keyMediaKey = 'mediaKey';
static const String _keyMediaIv = 'mediaIv';

// Update build() signature — add two optional params after mediaDuration:
static Map<String, dynamic> build(
  String content, {
  String messageType = 'TEXT',
  String? mediaUrl,
  int? mediaDuration,
  String? mediaKey,    // NEW
  String? mediaIv,     // NEW
  Map<String, String?>? linkPreview,
}) {
  final envelope = <String, dynamic>{_keyContent: content};
  if (messageType != 'TEXT') envelope[_keyMessageType] = messageType;
  if (mediaUrl != null) envelope[_keyMediaUrl] = mediaUrl;
  if (mediaDuration != null) envelope[_keyMediaDuration] = mediaDuration;
  if (mediaKey != null) envelope[_keyMediaKey] = mediaKey;   // NEW
  if (mediaIv != null) envelope[_keyMediaIv] = mediaIv;      // NEW
  if (linkPreview != null) envelope[_keyLinkPreview] = linkPreview;
  return envelope;
}

// Update parse() return record — add two new fields:
static ({
  String content,
  String messageType,
  String? mediaUrl,
  int? mediaDuration,
  String? mediaKey,        // NEW
  String? mediaIv,         // NEW
  String? linkPreviewUrl,
  String? linkPreviewTitle,
  String? linkPreviewImageUrl,
}) parse(String jsonStr) {
  final envelope = jsonDecode(jsonStr) as Map<String, dynamic>;
  // ... existing parsing unchanged ...
  return (
    content: content,
    messageType: messageType,
    mediaUrl: mediaUrl,
    mediaDuration: mediaDuration,
    mediaKey: envelope[_keyMediaKey] as String?,   // NEW
    mediaIv: envelope[_keyMediaIv] as String?,     // NEW
    linkPreviewUrl: lp?[_keyUrl] as String?,
    linkPreviewTitle: lp?[_keyTitle] as String?,
    linkPreviewImageUrl: lp?[_keyImageUrl] as String?,
  );
}
```

**Important:** After updating `parse()`, search for all callers of `E2eEnvelope.parse()` in the codebase:
```bash
grep -rn "E2eEnvelope.parse\|\.parse(" frontend/lib --include="*.dart"
```
For each caller that destructures the result, update to include `mediaKey` and `mediaIv` fields (they can be ignored with `_` or used as needed).

- [ ] **Step 4: Update ApiService — replace uploadMedia with uploadEncryptedMedia**

In `frontend/lib/services/api_service.dart`, add a new method (keep old `uploadMedia` temporarily if other callers need it during migration, or replace directly):

```dart
/// Upload an AES-encrypted media blob to /media/upload.
/// [encryptedBytes]: ciphertext from MediaCryptoService.encrypt()
/// [mediaType]: 'image' | 'voice' | 'gif' | 'file'
///
/// Note: upload progress tracking is not implemented here because Flutter's
/// http.MultipartRequest does not expose send-side progress. The UX relies on
/// the encrypt phase (spinner) + fast upload for typical file sizes. A future
/// iteration can replace with Dio's onSendProgress if needed.
Future<Map<String, dynamic>> uploadEncryptedMedia({
  required String token,
  required Uint8List encryptedBytes,
  required String mediaType,
  int? duration,
  int? expiresIn,
  String? fileName,
}) async {
  final uri = Uri.parse('$baseUrl/media/upload');
  final request = http.MultipartRequest('POST', uri);
  request.headers['Authorization'] = 'Bearer $token';
  request.fields['mediaType'] = mediaType;
  if (duration != null) request.fields['duration'] = duration.toString();
  if (expiresIn != null) request.fields['expiresIn'] = expiresIn.toString();
  if (fileName != null) request.fields['fileName'] = fileName;

  request.files.add(http.MultipartFile.fromBytes(
    'file',
    encryptedBytes,
    filename: 'encrypted.bin',
    contentType: MediaType('application', 'octet-stream'),
  ));

  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception(data['message'] ?? 'Upload failed');
  }
  return data;
}
```

- [ ] **Step 5: Run all tests**

```bash
cd frontend && flutter test
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/utils/e2e_envelope.dart frontend/lib/services/api_service.dart \
        frontend/test/utils/e2e_envelope_test.dart
git commit -m "feat(frontend): extend E2eEnvelope with mediaKey/mediaIv; add uploadEncryptedMedia to ApiService"
```

---

### Task 9: Encrypt before upload — sendImage, sendVoice, sendGif, sendFile

**Files:**
- Modify: `frontend/lib/providers/messaging_provider.dart`

This task updates all four send methods. The pattern is identical for each:
1. Encrypt bytes with `MediaCryptoService` (in `compute()`, UI-safe)
2. Write `_pendingSendContent[tempId]` with `mediaKey` + `mediaIv` **before** any await
3. Upload encrypted blob via `uploadEncryptedMedia`
4. Pass key+IV into `_encryptAndSend`

- [ ] **Step 1: Add MediaCryptoService import + field**

At the top of `messaging_provider.dart`, add:
```dart
import '../services/media_crypto_service.dart';
```

Add field to `MessagingProvider`:
```dart
final MediaCryptoService _mediaCrypto = MediaCryptoService();
```

- [ ] **Step 2: Update sendImage()**

Find the `sendImage()` method (~line 660). After the optimistic message is created and before the `try` block, the pattern becomes:

```dart
// In the try block, replace:
//   final responseData = await _api.uploadMedia(token: token, type: 'image', imageFile: imageFile, ...)
// With:

final rawBytes = await imageFile.readAsBytes();
// Step A: encrypt in background isolate
final encrypted = await _mediaCrypto.encrypt(Uint8List.fromList(rawBytes));

// Step B: write _pendingSendContent with key+IV BEFORE any further awaits
_pendingSendContent[tempId] = <String, dynamic>{
  'content': '',
  'messageType': 'IMAGE',
  'mediaKey': encrypted.keyBase64,
  'mediaIv': encrypted.ivBase64,
};

// Step C: upload encrypted blob with progress
final responseData = await _api.uploadEncryptedMedia(
  token: token,
  encryptedBytes: encrypted.ciphertext,
  mediaType: 'image',
  expiresIn: effectiveExpiresIn,
);
// Note: no onProgress — uploadEncryptedMedia does not expose upload progress (MultipartRequest limitation).
// UX: indeterminate spinner shown during compute(encrypt); after that upload is fast for typical file sizes.

final mediaUrl = responseData['mediaUrl'] as String;
_pendingSendContent[tempId]!['mediaUrl'] = mediaUrl;

// Step D: encrypt and send (passes key+IV through envelope)
_encryptAndSend(
  recipientId: recipientId,
  content: '',
  tempId: tempId,
  effectiveExpiresIn: effectiveExpiresIn,
  messageType: 'IMAGE',
  mediaUrl: mediaUrl,
  mediaKey: encrypted.keyBase64,
  mediaIv: encrypted.ivBase64,
);
```

- [ ] **Step 3: Update _encryptAndSend() signature**

Find `_encryptAndSend()` and add optional params:
```dart
Future<void> _encryptAndSend({
  required int recipientId,
  required String content,
  required String tempId,
  int? effectiveExpiresIn,
  String messageType = 'TEXT',
  String? mediaUrl,
  int? mediaDuration,
  String? mediaKey,   // NEW
  String? mediaIv,    // NEW
  Map<String, String?>? linkPreview,
}) async {
  // ... existing session/encrypt logic ...
  // In E2eEnvelope.build() call, add:
  final envelope = E2eEnvelope.build(
    content,
    messageType: messageType,
    mediaUrl: mediaUrl,
    mediaDuration: mediaDuration,
    mediaKey: mediaKey,   // NEW
    mediaIv: mediaIv,     // NEW
    linkPreview: linkPreview,
  );
  // rest unchanged...
}
```

- [ ] **Step 4: Update sendVoice()**

Same pattern as sendImage. Note: **measure duration before encrypting**:
```dart
// Voice: duration comes from the existing dto.duration or is measured by RecordingController
// It is already available as the `duration` parameter — pass it directly:
final encrypted = await _mediaCrypto.encrypt(Uint8List.fromList(audioBytes));
_pendingSendContent[tempId] = <String, dynamic>{
  'content': '', 'messageType': 'VOICE',
  'mediaDuration': duration,
  'mediaKey': encrypted.keyBase64, 'mediaIv': encrypted.ivBase64,
};
final responseData = await _api.uploadEncryptedMedia(
  token: token, encryptedBytes: encrypted.ciphertext,
  mediaType: 'voice', duration: duration, expiresIn: effectiveExpiresIn,
);
```

- [ ] **Step 5: Update sendGif() and sendFile()**

Apply same encrypt-before-upload pattern. For `sendFile`, pass `fileName` to `uploadEncryptedMedia`.

- [ ] **Step 6: Run analyzer**

```bash
cd frontend && flutter analyze
```
Fix any warnings before continuing.

- [ ] **Step 7: Run all tests**

```bash
cd frontend && flutter test
```
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add frontend/lib/providers/messaging_provider.dart
git commit -m "feat(frontend): encrypt media before upload in all send methods (AES-256-GCM via compute)"
```

---

### Task 10: Decrypt on receive — image, voice, GIF, file widgets

**Files:**
- Modify: `frontend/lib/widgets/message/image_message_content.dart`
- Modify: `frontend/lib/widgets/message/voice_message_content.dart`
- Modify: `frontend/lib/widgets/message/gif_message_content.dart`
- Modify: `frontend/lib/widgets/message/file_message_content.dart`
- Modify: `frontend/lib/providers/messaging_provider.dart` (receive path)

- [ ] **Step 1: Update receive path in messaging_provider.dart**

In `_decryptMessageHistory` and `onNewMessage` handlers, after `E2eEnvelope.parse()`, extract `mediaKey` and `mediaIv` and pass them into the message model via `copyWith`:

```dart
final parsed = E2eEnvelope.parse(encryptedContent);
// existing copyWith:
message.copyWith(
  content: parsed.content,
  messageType: MessageType.fromString(parsed.messageType),
  mediaUrl: parsed.mediaUrl,
  mediaDuration: parsed.mediaDuration,
  mediaKey: parsed.mediaKey,     // NEW — add to MessageModel if not present
  mediaIv: parsed.mediaIv,       // NEW
  linkPreviewUrl: parsed.linkPreviewUrl,
  // ...
)
```

If `MessageModel` doesn't have `mediaKey`/`mediaIv` fields, add them now:
- In `frontend/lib/models/message_model.dart`: add `final String? mediaKey; final String? mediaIv;` fields
- Add to constructor: `this.mediaKey, this.mediaIv`
- Add to `fromJson`: `mediaKey: json['mediaKey'] as String?, mediaIv: json['mediaIv'] as String?`
- **CRITICAL — add to `copyWith()`**: `String? mediaKey, String? mediaIv` params with `mediaKey: mediaKey ?? this.mediaKey, mediaIv: mediaIv ?? this.mediaIv` (per CLAUDE.md rule: missing copyWith field = data silently lost on every status update)

- [ ] **Step 2: Update ImageMessageContent — fetch + decrypt before display**

In `frontend/lib/widgets/message/image_message_content.dart`, replace the direct `Image.network(message.mediaUrl)` with:

```dart
// In initState or a FutureBuilder:
Future<Uint8List?> _loadDecrypted() async {
  final url = widget.message.mediaUrl;
  final key = widget.message.mediaKey;
  final iv = widget.message.mediaIv;
  if (url == null) return null;

  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) throw Exception('Failed to fetch media');

  if (key != null && iv != null) {
    final service = MediaCryptoService();
    return service.decrypt(response.bodyBytes, key, iv);
  }
  // Legacy: no key = unencrypted Cloudinary URL
  return response.bodyBytes;
}

// Render:
FutureBuilder<Uint8List?>(
  future: _loadDecrypted(),
  builder: (context, snap) {
    if (snap.connectionState != ConnectionState.done) {
      return const SizedBox(width: 200, height: 150, child: Center(child: CircularProgressIndicator()));
    }
    if (snap.data == null) return const Icon(Icons.broken_image);
    return Image.memory(snap.data!, fit: BoxFit.cover);
  },
)
```

- [ ] **Step 3: Update PlaybackController (voice decrypt)**

Voice audio is loaded by `PlaybackController` (in `frontend/lib/widgets/audio/playback_controller.dart`), not by `VoiceMessageContent` directly. `VoiceMessageContent` is a stateless wrapper — all loading happens inside `PlaybackController._loadAndPlayAudio()`.

Update `_loadAndPlayAudio()` in `playback_controller.dart`:

```dart
Future<void> _loadAndPlayAudio() async {
  final url = widget.message.mediaUrl;
  if (url == null) return;
  final mediaKey = widget.message.mediaKey;
  final mediaIv = widget.message.mediaIv;

  // Determine cache path — use .audio extension (per CLAUDE.md rule; avoids confusion with legacy unencrypted .m4a cache)
  final cacheFile = File('${(await getTemporaryDirectory()).path}/audio_cache/${widget.message.id}.audio');

  Uint8List audioBytes;
  if (await cacheFile.exists()) {
    audioBytes = await cacheFile.readAsBytes();
  } else {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) throw Exception('Failed to fetch audio');
    if (mediaKey != null && mediaIv != null) {
      // Decrypt in background isolate
      audioBytes = await MediaCryptoService().decrypt(response.bodyBytes, mediaKey, mediaIv);
    } else {
      // Legacy unencrypted Cloudinary audio
      audioBytes = response.bodyBytes;
    }
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsBytes(audioBytes);
  }
  // Continue existing audio player initialization with audioBytes / cacheFile.path...
}
```

- [ ] **Step 4: Update GifMessageContent**

Fetch → decrypt → on web: create blob URL; on native: `Image.memory`.

```dart
// After decrypt:
if (kIsWeb) {
  // Use existing blob URL pattern from this widget
  final blobUrl = _createBlobUrl(decryptedBytes, 'image/gif');
  // Image.network(blobUrl)
} else {
  // Image.memory(decryptedBytes)
}
```

Legacy (no `mediaKey`): keep existing behavior unchanged.

- [ ] **Step 5: Update FileMessageContent**

`FileMessageContent` uses `download_utils.downloadFile(url, filename)` from a conditional import (`file_utils_web.dart` / `file_utils_io.dart`). Preserve this abstraction:

- **Legacy path (no `mediaKey`):** keep `download_utils.downloadFile(mediaUrl, fileName)` unchanged
- **New encrypted path (native):** fetch blob → `MediaCryptoService().decrypt(bytes, key, iv)` → write to temp file → trigger download via same `download_utils` abstraction or `launchUrl(Uri.file(tempPath))`
- **New encrypted path (web):** fetch blob → decrypt → create `Blob` → `Url.createObjectUrl(blob)` → trigger `AnchorElement` click to download (standard browser download pattern; cannot use `Uri.file` on web)

Do NOT use `launchUrl` for legacy path — the existing implementation does not use it.

- [ ] **Step 6: Run full test suite + analyzer**

```bash
cd frontend && flutter analyze && flutter test
```
Expected: zero warnings, all tests pass.

- [ ] **Step 7: Manual smoke test**

1. Run the app, log in as User A on one device/tab
2. Send an image to User B
3. On User B's device/tab: image should appear (decrypted)
4. Check network tab — the fetched `/media/msgs/*.bin` response should be binary gibberish (ciphertext), not a valid image
5. Send a voice message, GIF, and file — verify each displays/plays correctly
6. Send a text message — verify it's unaffected

- [ ] **Step 8: Commit**

```bash
git add frontend/lib/widgets/message/image_message_content.dart \
        frontend/lib/widgets/message/voice_message_content.dart \
        frontend/lib/widgets/message/gif_message_content.dart \
        frontend/lib/widgets/message/file_message_content.dart \
        frontend/lib/widgets/audio/playback_controller.dart \
        frontend/lib/models/message_model.dart \
        frontend/lib/providers/messaging_provider.dart
git commit -m "feat(frontend): decrypt media on receive in all message type widgets"
```

---

### Task 11: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md to reflect new reality**

Update the following sections in `CLAUDE.md`:

1. **Section 0 (Quick Start):** Remove Cloudinary env vars; note `MEDIA_BASE_URL` and `MEDIA_DIR`
2. **Section 1 (Critical Rules — E2E Encryption):** Replace description of `MediaCryptoService` as "planned but not implemented" with accurate description of `media_crypto_service.dart`
3. **Section 2 (Architecture — State Management):** Add `MediaCryptoService` to services list
4. **Section 3 (File Location Map — Frontend):** Add `services/media_crypto_service.dart`; add `utils/e2e_envelope.dart`
5. **Section 7 (REST API):** Remove `POST /messages/upload-media`; add `POST /media/upload`, `GET /media/msgs/:filename`, `GET /media/avatars/:filename`
6. **Section 10 (Environment):** Replace Cloudinary vars with `MEDIA_BASE_URL` and `MEDIA_DIR`
7. **Section 11 (Known Limitations):** Update media encryption description — it IS implemented now

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md to reflect self-hosted media + MediaCryptoService implementation"
```

---

## ═══════════════════════════════════════
## VERIFICATION CHECKLIST
## ═══════════════════════════════════════

Run before declaring done:

- [ ] `cd backend && npm test` — all tests pass
- [ ] `cd frontend && flutter test` — all tests pass
- [ ] `cd frontend && flutter analyze` — zero warnings
- [ ] Manual: send image → visible on recipient's screen, network blob is ciphertext
- [ ] Manual: send voice → plays on recipient, blob is ciphertext
- [ ] Manual: send GIF → animates on recipient (web + native)
- [ ] Manual: send file → opens on recipient
- [ ] Manual: old Cloudinary message still loads (backward compat)
- [ ] Manual: avatar upload works, avatar visible to contacts
- [ ] Manual: text message unaffected (Signal E2E unchanged)
- [ ] Production deploy: `~/deploy.sh` on VM — verify `media_storage` volume persists across redeploys
