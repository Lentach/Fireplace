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

    function mockValidMediaUrls(urls: string[]) {
      const queryBuilder = {
        select: jest.fn().mockReturnThis(),
        where: jest.fn().mockReturnThis(),
        andWhere: jest.fn().mockReturnThis(),
        getRawMany: jest.fn().mockResolvedValue(urls.map((mediaUrl) => ({ mediaUrl }))),
      };
      mockMessageRepo.createQueryBuilder.mockReturnValue(queryBuilder);
      return queryBuilder;
    }

    it('does not delete disk file referenced by a message row', async () => {
      const referenced = 'referenced.bin';
      const orphan = 'orphan-only.bin';
      await fs.writeFile(path.join(msgsDir, referenced), 'referenced-data');
      await fs.writeFile(path.join(msgsDir, orphan), 'orphan-data');

      mockValidMediaUrls([
        `${MEDIA_BASE_URL}/media/msgs/${referenced}`,
      ]);

      await cronService.cleanupOrphanedFiles();

      await expect(
        fs.access(path.join(msgsDir, referenced)),
      ).resolves.toBeUndefined();
      await expect(fs.access(path.join(msgsDir, orphan))).rejects.toThrow();
    });

    it('deletes disk files with no matching message mediaUrl', async () => {
      const orphanA = 'stale-a.bin';
      const orphanB = 'stale-b.bin';
      await fs.writeFile(path.join(msgsDir, orphanA), 'a');
      await fs.writeFile(path.join(msgsDir, orphanB), 'b');

      mockValidMediaUrls([]);

      await cronService.cleanupOrphanedFiles();

      await expect(fs.access(path.join(msgsDir, orphanA))).rejects.toThrow();
      await expect(fs.access(path.join(msgsDir, orphanB))).rejects.toThrow();
    });

    it('skips cleanup when msgs dir is missing', async () => {
      const emptyDir = await fs.mkdtemp(
        path.join(os.tmpdir(), 'fireplace-media-empty-'),
      );
      try {
        const emptyService = await createService(emptyDir);
        mockValidMediaUrls([]);
        await expect(emptyService.cleanupOrphanedFiles()).resolves.not.toThrow();
        expect(mockMessageRepo.createQueryBuilder).not.toHaveBeenCalled();
      } finally {
        await fs.rm(emptyDir, { recursive: true, force: true });
      }
    });
  });
});
