import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { WebPushSubscription } from './web-push-subscription.entity';
import { WebPushSubscriptionsService } from './web-push-subscriptions.service';

/**
 * Per-device push targeting (Phase 1 columns, spec §5.5 teardown + §12
 * amendment (xxiv)).
 *
 * The teardown's WHERE clause is the whole security property here: a revoked
 * device that keeps a live endpoint keeps receiving notifications about
 * messages it is no longer served.
 */
describe('WebPushSubscriptionsService', () => {
  let service: WebPushSubscriptionsService;
  let repo: Record<string, jest.Mock>;
  let builder: {
    delete: jest.Mock;
    from: jest.Mock;
    where: jest.Mock;
    andWhere: jest.Mock;
    execute: jest.Mock;
  };
  let clauses: Array<[string, unknown]>;

  beforeEach(async () => {
    clauses = [];
    builder = {
      delete: jest.fn().mockReturnThis(),
      from: jest.fn().mockReturnThis(),
      where: jest.fn((clause: string, params: unknown) => {
        clauses.push([clause, params]);
        return builder;
      }),
      andWhere: jest.fn((clause: string, params: unknown) => {
        clauses.push([clause, params]);
        return builder;
      }),
      execute: jest.fn().mockResolvedValue({ affected: 1 }),
    };
    repo = {
      upsert: jest.fn().mockResolvedValue({ raw: [] }),
      delete: jest.fn().mockResolvedValue({ affected: 0 }),
      find: jest.fn().mockResolvedValue([]),
      createQueryBuilder: jest.fn(() => builder),
    };
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        WebPushSubscriptionsService,
        {
          provide: getRepositoryToken(WebPushSubscription),
          useValue: repo,
        },
      ],
    }).compile();
    service = module.get(WebPushSubscriptionsService);
  });

  it('persists the registering device id, so a revoke can find the row', async () => {
    await service.upsert({
      userId: 7,
      deviceId: 2,
      endpoint: 'https://push.example/abc',
      p256dh: 'p',
      auth: 'a',
    });

    expect(repo.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ userId: 7, deviceId: 2 }),
      ['endpoint'],
    );
  });

  it('writes NULL when the caller has no device id, never a guess', async () => {
    await service.upsert({
      userId: 7,
      endpoint: 'https://push.example/abc',
      p256dh: 'p',
      auth: 'a',
    });

    expect(repo.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ deviceId: null }),
      ['endpoint'],
    );
  });

  it('removeForDevice deletes that device rows AND the unattributable ones', async () => {
    await service.removeForDevice(7, 2);

    expect(clauses).toEqual([
      ['"userId" = :userId', { userId: 7 }],
      ['("deviceId" = :deviceId OR "deviceId" IS NULL)', { deviceId: 2 }],
    ]);
    expect(builder.execute).toHaveBeenCalledTimes(1);
  });

  it('never deletes another live device rows', async () => {
    await service.removeForDevice(7, 2);

    // Amendment (xxiv) resolves the NULL ambiguity toward cutting the revoked
    // device off — but a row that names a DIFFERENT device is out of scope,
    // otherwise revoking one device would silence the whole account.
    const [, deviceClause] = clauses[1];
    expect(deviceClause).toEqual({ deviceId: 2 });
    expect(clauses[1][0]).not.toContain('!=');
  });
});
