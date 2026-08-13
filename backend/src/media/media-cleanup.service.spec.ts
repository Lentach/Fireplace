import { Test } from '@nestjs/testing';
import { MediaCleanupService } from './media-cleanup.service';
import { LocalStorageService } from './local-storage.service';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Message } from '../messages/message.entity';
import * as fs from 'fs/promises';
import * as os from 'os';
import * as path from 'path';

const mockStorage = {
  deleteFile: jest.fn().mockResolvedValue(undefined),
  extractPublicId: jest.fn((url: string) =>
    url.replace('https://example.com/media/', ''),
  ),
};
const mockMessageRepo = { createQueryBuilder: jest.fn() };

const MEDIA_BASE_URL = 'https://example.com';

async function createService(mediaDir: string): Promise<MediaCleanupService> {
  const module = await Test.createTestingModule({
    providers: [
      MediaCleanupService,
      { provide: LocalStorageService, useValue: mockStorage },
      { provide: getRepositoryToken(Message), useValue: mockMessageRepo },
      { provide: 'MEDIA_BASE_URL', useValue: MEDIA_BASE_URL },
      { provide: 'MEDIA_DIR', useValue: mediaDir },
    ],
  }).compile();
  return module.get(MediaCleanupService);
}

describe('MediaCleanupService', () => {
  let service: MediaCleanupService;

  beforeEach(async () => {
    jest.clearAllMocks();
    service = await createService('/app/media');
  });

  it('deleteMediaFile skips null mediaUrl', async () => {
    await service.deleteMediaFile(null);
    expect(mockStorage.deleteFile).not.toHaveBeenCalled();
  });

  it('deleteMediaFile skips Cloudinary URLs', async () => {
    await service.deleteMediaFile(
      'https://res.cloudinary.com/demo/image/upload/sample.jpg',
    );
    expect(mockStorage.deleteFile).not.toHaveBeenCalled();
  });

  it('deleteMediaFile calls deleteFile with publicId for self-hosted URLs', async () => {
    await service.deleteMediaFile('https://example.com/media/msgs/abc.bin');
    expect(mockStorage.extractPublicId).toHaveBeenCalledWith(
      'https://example.com/media/msgs/abc.bin',
    );
    expect(mockStorage.deleteFile).toHaveBeenCalledWith('msgs/abc.bin');
  });

  it('deleteMediaFile does not throw on storage error', async () => {
    mockStorage.deleteFile.mockRejectedValueOnce(new Error('disk error'));
    await expect(
      service.deleteMediaFile('https://example.com/media/msgs/abc.bin'),
    ).resolves.not.toThrow();
  });

  describe('cleanupOrphanedFiles', () => {
    let tempMediaDir: string;
    let msgsDir: string;
    let cronService: MediaCleanupService;

    beforeEach(async () => {
      tempMediaDir = await fs.mkdtemp(
        path.join(os.tmpdir(), 'fireplace-media-cleanup-'),
      );
      msgsDir = path.join(tempMediaDir, 'msgs');
      await fs.mkdir(msgsDir, { recursive: true });
      cronService = await createService(tempMediaDir);
    });

    afterEach(async () => {
      await fs.rm(tempMediaDir, { recursive: true, force: true });
    });

    // Comfortably older than the 15-min default grace window so a backdated
    // file is eligible for deletion.
    const AGED_MS = 20 * 60 * 1000;

    /** Sticky mock: both cleanup queries (valid + all-referenced) see `urls`. */
    function mockValidMediaUrls(urls: string[]) {
      const queryBuilder = {
        select: jest.fn().mockReturnThis(),
        where: jest.fn().mockReturnThis(),
        andWhere: jest.fn().mockReturnThis(),
        getRawMany: jest
          .fn()
          .mockResolvedValue(urls.map((mediaUrl) => ({ mediaUrl }))),
      };
      mockMessageRepo.createQueryBuilder.mockReturnValue(queryBuilder);
      return queryBuilder;
    }

    /**
     * Distinct results per query: first call = non-expired rows (`valid`),
     * second call = ALL referenced rows (`referenced`). A filename in
     * `referenced` but not `valid` is an EXPIRED file; in neither is an ORPHAN.
     */
    function mockMediaUrls(opts: { valid: string[]; referenced: string[] }) {
      const makeBuilder = (urls: string[]) => ({
        select: jest.fn().mockReturnThis(),
        where: jest.fn().mockReturnThis(),
        andWhere: jest.fn().mockReturnThis(),
        getRawMany: jest
          .fn()
          .mockResolvedValue(urls.map((mediaUrl) => ({ mediaUrl }))),
      });
      mockMessageRepo.createQueryBuilder
        .mockReturnValueOnce(makeBuilder(opts.valid))
        .mockReturnValueOnce(makeBuilder(opts.referenced));
    }

    /** Write a file then backdate its mtime by `ageMs` (to age past grace). */
    async function writeAged(name: string, ageMs: number) {
      const p = path.join(msgsDir, name);
      await fs.writeFile(p, name);
      const pastSeconds = (Date.now() - ageMs) / 1000;
      await fs.utimes(p, pastSeconds, pastSeconds);
    }

    it('does not delete disk file referenced by a message row', async () => {
      const referenced = 'referenced.bin';
      const orphan = 'orphan-only.bin';
      await fs.writeFile(path.join(msgsDir, referenced), 'referenced-data');
      await writeAged(orphan, AGED_MS); // aged so grace does not protect it

      mockValidMediaUrls([`${MEDIA_BASE_URL}/media/msgs/${referenced}`]);

      await cronService.cleanupOrphanedFiles();

      await expect(
        fs.access(path.join(msgsDir, referenced)),
      ).resolves.toBeUndefined();
      await expect(fs.access(path.join(msgsDir, orphan))).rejects.toThrow();
    });

    it('deletes disk files with no matching message mediaUrl', async () => {
      const orphanA = 'stale-a.bin';
      const orphanB = 'stale-b.bin';
      await writeAged(orphanA, AGED_MS);
      await writeAged(orphanB, AGED_MS);

      mockValidMediaUrls([]);

      await cronService.cleanupOrphanedFiles();

      await expect(fs.access(path.join(msgsDir, orphanA))).rejects.toThrow();
      await expect(fs.access(path.join(msgsDir, orphanB))).rejects.toThrow();
    });

    it('does not delete a recently-created unreferenced file (within grace)', async () => {
      // mtime ≈ now → an in-flight upload whose send emit has not landed yet.
      await fs.writeFile(path.join(msgsDir, 'in-flight.bin'), 'x');

      mockMediaUrls({ valid: [], referenced: [] });

      const summary = await cronService.cleanupOrphanedFiles();

      expect(summary.graceSkipped).toBe(1);
      expect(summary.deleted).toBe(0);
      await expect(
        fs.access(path.join(msgsDir, 'in-flight.bin')),
      ).resolves.toBeUndefined();
    });

    it('deletes an old unreferenced orphan (older than grace)', async () => {
      await writeAged('old-orphan.bin', AGED_MS);

      mockMediaUrls({ valid: [], referenced: [] });

      const summary = await cronService.cleanupOrphanedFiles();

      expect(summary.deleted).toBe(1);
      expect(summary.orphan).toBe(1);
      expect(summary.graceSkipped).toBe(0);
      await expect(
        fs.access(path.join(msgsDir, 'old-orphan.bin')),
      ).rejects.toThrow();
    });

    it('classifies deleted files as orphan vs expired and skips grace', async () => {
      // live.bin: referenced by a non-expired row → kept
      // expired.bin: referenced by a row that is expired → deleted as EXPIRED
      // orphan.bin: referenced by no row → deleted as ORPHAN
      // recent-orphan.bin: referenced by no row but younger than grace → skipped
      await fs.writeFile(path.join(msgsDir, 'live.bin'), 'l');
      await writeAged('expired.bin', AGED_MS);
      await writeAged('orphan.bin', AGED_MS);
      await fs.writeFile(path.join(msgsDir, 'recent-orphan.bin'), 'r');

      mockMediaUrls({
        valid: [`${MEDIA_BASE_URL}/media/msgs/live.bin`],
        referenced: [
          `${MEDIA_BASE_URL}/media/msgs/live.bin`,
          `${MEDIA_BASE_URL}/media/msgs/expired.bin`,
        ],
      });

      const summary = await cronService.cleanupOrphanedFiles();

      expect(summary).toEqual({
        scanned: 4,
        deleted: 2,
        orphan: 1,
        expired: 1,
        graceSkipped: 1,
      });
      await expect(
        fs.access(path.join(msgsDir, 'live.bin')),
      ).resolves.toBeUndefined();
      await expect(
        fs.access(path.join(msgsDir, 'recent-orphan.bin')),
      ).resolves.toBeUndefined();
      await expect(
        fs.access(path.join(msgsDir, 'expired.bin')),
      ).rejects.toThrow();
      await expect(
        fs.access(path.join(msgsDir, 'orphan.bin')),
      ).rejects.toThrow();
    });

    describe('grace window env parsing (resolveGraceMs)', () => {
      const GRACE_VAR = 'MEDIA_CLEANUP_GRACE_MS';
      let savedGrace: string | undefined;

      beforeEach(() => {
        savedGrace = process.env[GRACE_VAR];
      });

      afterEach(() => {
        if (savedGrace === undefined) delete process.env[GRACE_VAR];
        else process.env[GRACE_VAR] = savedGrace;
      });

      // A file written ~now sits inside the 15-min default grace window: it is
      // an in-flight upload and must be preserved when the default applies.
      async function runWithFreshOrphan() {
        await fs.writeFile(path.join(msgsDir, 'fresh-orphan.bin'), 'x');
        mockMediaUrls({ valid: [], referenced: [] });
        return cronService.cleanupOrphanedFiles();
      }

      it('treats empty-string env as unset → default grace (not zero)', async () => {
        // Number('') === 0 would silently disable the grace window and delete
        // the in-flight file; the fix must fall back to the 15-min default.
        process.env[GRACE_VAR] = '';
        const summary = await runWithFreshOrphan();
        expect(summary.graceSkipped).toBe(1);
        expect(summary.deleted).toBe(0);
        await expect(
          fs.access(path.join(msgsDir, 'fresh-orphan.bin')),
        ).resolves.toBeUndefined();
      });

      it('treats whitespace-only env as unset → default grace', async () => {
        process.env[GRACE_VAR] = '   ';
        const summary = await runWithFreshOrphan();
        expect(summary.graceSkipped).toBe(1);
        expect(summary.deleted).toBe(0);
      });

      it('falls back to default grace for a non-numeric env value', async () => {
        process.env[GRACE_VAR] = 'not-a-number';
        const summary = await runWithFreshOrphan();
        expect(summary.graceSkipped).toBe(1);
        expect(summary.deleted).toBe(0);
      });

      it('honours an explicit valid grace value (0 disables the window)', async () => {
        // A deliberate MEDIA_CLEANUP_GRACE_MS=0 is a valid, distinct choice
        // from an empty string: with no grace the fresh orphan is swept.
        process.env[GRACE_VAR] = '0';
        const summary = await runWithFreshOrphan();
        expect(summary.graceSkipped).toBe(0);
        expect(summary.deleted).toBe(1);
        await expect(
          fs.access(path.join(msgsDir, 'fresh-orphan.bin')),
        ).rejects.toThrow();
      });

      it('sweeps an orphan whose mtime is in the future (age clamped at 0)', async () => {
        // NTFS rounds a just-written mtime up past the captured nowMs, so a raw
        // nowMs - mtimeMs goes negative and reports the orphan as "fresh".
        // Exaggerated here to a full hour ahead so the assertion is not a race.
        process.env[GRACE_VAR] = '0';
        const target = path.join(msgsDir, 'fresh-orphan.bin');
        await fs.writeFile(target, 'x');
        const future = new Date(Date.now() + 3_600_000);
        await fs.utimes(target, future, future);
        mockMediaUrls({ valid: [], referenced: [] });
        const summary = await cronService.cleanupOrphanedFiles();
        expect(summary.graceSkipped).toBe(0);
        expect(summary.deleted).toBe(1);
        await expect(fs.access(target)).rejects.toThrow();
      });
    });

    it('skips cleanup when msgs dir is missing', async () => {
      const emptyDir = await fs.mkdtemp(
        path.join(os.tmpdir(), 'fireplace-media-empty-'),
      );
      try {
        const emptyService = await createService(emptyDir);
        mockValidMediaUrls([]);
        await expect(
          emptyService.cleanupOrphanedFiles(),
        ).resolves.not.toThrow();
        expect(mockMessageRepo.createQueryBuilder).not.toHaveBeenCalled();
      } finally {
        await fs.rm(emptyDir, { recursive: true, force: true });
      }
    });
  });
});
