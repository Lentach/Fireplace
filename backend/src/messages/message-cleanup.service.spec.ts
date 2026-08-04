import { getRepositoryToken } from '@nestjs/typeorm';
import { Test } from '@nestjs/testing';
import { Repository } from 'typeorm';
import { MediaCleanupService } from '../media/media-cleanup.service';
import { Message } from './message.entity';
import { MessageCleanupService } from './message-cleanup.service';

describe('MessageCleanupService', () => {
  let service: MessageCleanupService;
  let messagesRepo: jest.Mocked<Repository<Message>>;
  let mediaCleanupService: jest.Mocked<
    Pick<MediaCleanupService, 'deleteMediaFile'>
  >;
  let queryBuilder: {
    where: jest.Mock;
    orWhere: jest.Mock;
    take: jest.Mock;
    getMany: jest.Mock;
  };

  beforeEach(async () => {
    queryBuilder = {
      where: jest.fn().mockReturnThis(),
      orWhere: jest.fn().mockReturnThis(),
      take: jest.fn().mockReturnThis(),
      getMany: jest.fn().mockResolvedValue([]),
    };

    const module = await Test.createTestingModule({
      providers: [
        MessageCleanupService,
        {
          provide: getRepositoryToken(Message),
          useValue: {
            createQueryBuilder: jest.fn().mockReturnValue(queryBuilder),
            remove: jest.fn().mockResolvedValue([]),
            query: jest.fn().mockResolvedValue([[], 0]),
          },
        },
        {
          provide: MediaCleanupService,
          useValue: {
            deleteMediaFile: jest.fn().mockResolvedValue(undefined),
          },
        },
      ],
    }).compile();

    service = module.get(MessageCleanupService);
    messagesRepo = module.get(getRepositoryToken(Message));
    mediaCleanupService = module.get(MediaCleanupService);
  });

  it('deletes media files (only non-null) before removing expired messages', async () => {
    const expired = [
      {
        id: 1,
        mediaUrl: 'https://example.com/media/msgs/a.bin',
        expiresAt: new Date(0),
      },
      { id: 2, mediaUrl: null, expiresAt: new Date(0) },
      {
        id: 3,
        mediaUrl: 'https://example.com/media/msgs/b.bin',
        expiresAt: new Date(0),
      },
    ] as Message[];
    queryBuilder.getMany.mockResolvedValue(expired);

    await service.deleteExpiredMessages();

    expect(messagesRepo.createQueryBuilder).toHaveBeenCalledWith('m');
    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledWith(
      'https://example.com/media/msgs/a.bin',
    );
    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledWith(
      'https://example.com/media/msgs/b.bin',
    );
    // Only the two non-null mediaUrls are deleted — the mediaUrl:null row (id 2)
    // must NOT trigger a deleteMediaFile call.
    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledTimes(2);
    expect(messagesRepo.remove).toHaveBeenCalledWith(expired);

    // Ordering: every media deletion must precede the DB removal.
    const lastDelete = Math.max(
      ...mediaCleanupService.deleteMediaFile.mock.invocationCallOrder,
    );
    const firstRemove = Math.min(
      ...messagesRepo.remove.mock.invocationCallOrder,
    );
    expect(lastDelete).toBeLessThan(firstRemove);

    // Reply detach (self-FK has no ON DELETE) runs before removal, covering
    // exactly the doomed ids — otherwise a parent expiring before its reply
    // throws 23503 and wedges the cron.
    const [detachSql, detachParams] = messagesRepo.query.mock.calls[0] as [
      string,
      unknown[],
    ];
    expect(detachSql).toContain('SET reply_to_message_id = NULL');
    expect(detachParams).toEqual([[1, 2, 3]]);
    expect(messagesRepo.query.mock.invocationCallOrder[0]).toBeLessThan(
      firstRemove,
    );
  });

  it('retains candidates that are not actually expired (isMessageExpired guard)', async () => {
    // The coarse SQL query may return rows that are not genuinely expired;
    // the service re-filters with isMessageExpired(m, now). A future-expiry row
    // must be retained: not removed, its media not deleted.
    const expiredRow = {
      id: 1,
      mediaUrl: 'https://example.com/media/msgs/expired.bin',
      expiresAt: new Date(0),
    } as unknown as Message;
    const futureRow = {
      id: 2,
      mediaUrl: 'https://example.com/media/msgs/future.bin',
      expiresAt: new Date(Date.now() + 60 * 60 * 1000),
    } as unknown as Message;
    queryBuilder.getMany.mockResolvedValue([expiredRow, futureRow]);

    await service.deleteExpiredMessages();

    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledWith(
      'https://example.com/media/msgs/expired.bin',
    );
    expect(mediaCleanupService.deleteMediaFile).not.toHaveBeenCalledWith(
      'https://example.com/media/msgs/future.bin',
    );
    expect(mediaCleanupService.deleteMediaFile).toHaveBeenCalledTimes(1);
    expect(messagesRepo.remove).toHaveBeenCalledWith([expiredRow]);
  });

  it('skips an overlapping tick while a previous run is still in flight', async () => {
    // The @Cron(EVERY_MINUTE) method is not serialised by NestJS. A prior run
    // that has not resolved must not let the next tick re-query the same
    // not-yet-removed rows and double the unlink concurrency.
    let releaseFirst!: (rows: Message[]) => void;
    const gate = new Promise<Message[]>((resolve) => {
      releaseFirst = resolve;
    });
    queryBuilder.getMany.mockReturnValueOnce(gate);

    // First tick enters, sets the guard, and parks on getMany (the guard is
    // set synchronously before the first await, so no flush is needed).
    const first = service.deleteExpiredMessages();
    expect(queryBuilder.getMany).toHaveBeenCalledTimes(1);

    // Second tick observes isRunning === true and returns without querying.
    await service.deleteExpiredMessages();
    expect(queryBuilder.getMany).toHaveBeenCalledTimes(1);

    releaseFirst([]);
    await first;
  });

  it('releases the guard after a throw so the next tick still runs', async () => {
    // The guard must be reset in finally: a run that throws (e.g. DB error)
    // must not wedge the cron permanently. First tick rejects; second runs.
    queryBuilder.getMany
      .mockRejectedValueOnce(new Error('boom'))
      .mockResolvedValue([]);

    await expect(service.deleteExpiredMessages()).rejects.toThrow('boom');

    await service.deleteExpiredMessages();
    expect(queryBuilder.getMany).toHaveBeenCalledTimes(2);
  });

  it('drains a backlog larger than one batch within a single tick', async () => {
    // A full batch means more may remain; the loop must keep querying within
    // the same tick rather than throttling to one batch per minute. BATCH=500
    // matches CLEANUP_BATCH_SIZE in the service.
    const BATCH = 500;
    const fullBatch = Array.from(
      { length: BATCH },
      (_, i) =>
        ({ id: i + 1, mediaUrl: null, expiresAt: new Date(0) }) as Message,
    );
    const tail = [
      { id: 10_001, mediaUrl: null, expiresAt: new Date(0) },
    ] as Message[];
    queryBuilder.getMany
      .mockResolvedValueOnce(fullBatch)
      .mockResolvedValueOnce(tail)
      .mockResolvedValue([]);

    await service.deleteExpiredMessages();

    // Full batch → loop continues; short tail batch → loop stops.
    expect(queryBuilder.getMany).toHaveBeenCalledTimes(2);
    expect(queryBuilder.take).toHaveBeenCalledWith(BATCH);
    expect(messagesRepo.remove).toHaveBeenCalledTimes(2);
    expect(messagesRepo.remove).toHaveBeenNthCalledWith(1, fullBatch);
    expect(messagesRepo.remove).toHaveBeenNthCalledWith(2, tail);
  });

  it('stops the drain loop when a full batch yields no genuinely-expired rows', async () => {
    // Coarse SQL can return rows that isMessageExpired rejects. If a whole
    // batch is non-expired, nothing is removed and re-querying would return
    // the same rows forever, so the loop must stop rather than spin.
    const BATCH = 500;
    const nonExpired = Array.from(
      { length: BATCH },
      (_, i) =>
        ({
          id: i + 1,
          mediaUrl: null,
          expiresAt: new Date(Date.now() + 60 * 60 * 1000),
        }) as unknown as Message,
    );
    queryBuilder.getMany.mockResolvedValue(nonExpired);

    await service.deleteExpiredMessages();

    // One query, no forward progress possible → break without spinning.
    expect(queryBuilder.getMany).toHaveBeenCalledTimes(1);
    expect(messagesRepo.remove).not.toHaveBeenCalled();
  });
});
