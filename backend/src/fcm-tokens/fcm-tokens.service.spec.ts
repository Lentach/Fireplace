import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { FcmToken } from './fcm-token.entity';
import { FcmTokensService } from './fcm-tokens.service';

/**
 * Per-device FCM targeting (Phase 1 column, spec §5.5 teardown + §12
 * amendment (xxiv)) — same law as web push: the revoked device's rows and the
 * account's unattributable rows go, and no other device's row does.
 */
describe('FcmTokensService', () => {
  let service: FcmTokensService;
  let repo: Record<string, jest.Mock>;
  let clauses: Array<[string, unknown]>;
  let execute: jest.Mock;

  beforeEach(async () => {
    clauses = [];
    execute = jest.fn().mockResolvedValue({ affected: 1 });
    const builder: Record<string, jest.Mock> = {
      delete: jest.fn(() => builder),
      from: jest.fn(() => builder),
      where: jest.fn((clause: string, params: unknown) => {
        clauses.push([clause, params]);
        return builder;
      }),
      andWhere: jest.fn((clause: string, params: unknown) => {
        clauses.push([clause, params]);
        return builder;
      }),
      execute,
    };
    repo = {
      upsert: jest.fn().mockResolvedValue({ raw: [] }),
      delete: jest.fn().mockResolvedValue({ affected: 0 }),
      find: jest.fn().mockResolvedValue([]),
      createQueryBuilder: jest.fn(() => builder),
    };
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        FcmTokensService,
        { provide: getRepositoryToken(FcmToken), useValue: repo },
      ],
    }).compile();
    service = module.get(FcmTokensService);
  });

  it('persists the registering device id', async () => {
    await service.upsert(7, 'token-abc', 'android', 2);

    expect(repo.upsert).toHaveBeenCalledWith(
      { userId: 7, token: 'token-abc', platform: 'android', deviceId: 2 },
      ['token'],
    );
  });

  it('defaults to NULL for a caller with no device id', async () => {
    await service.upsert(7, 'token-abc', 'android');

    expect(repo.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ deviceId: null }),
      ['token'],
    );
  });

  it('removeForDevice deletes that device rows AND the unattributable ones', async () => {
    await service.removeForDevice(7, 2);

    expect(clauses).toEqual([
      ['"userId" = :userId', { userId: 7 }],
      ['("deviceId" = :deviceId OR "deviceId" IS NULL)', { deviceId: 2 }],
    ]);
    expect(execute).toHaveBeenCalledTimes(1);
  });
});
