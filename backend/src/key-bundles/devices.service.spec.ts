import { Logger } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { Device } from './device.entity';
import { DevicesService } from './devices.service';

/**
 * The account's device rows (Phase 1, multi-device spec §4).
 *
 * Two properties matter here: the row exists for every account that connects
 * (a table only a migration backfill ever wrote would be dead by the time
 * revocation needs it), and touching it can never break a connection.
 */
describe('DevicesService', () => {
  let service: DevicesService;
  let repo: Record<string, jest.Mock>;
  let warnSpy: jest.SpyInstance;

  beforeEach(async () => {
    repo = {
      update: jest.fn().mockResolvedValue({ affected: 0 }),
      insert: jest.fn().mockResolvedValue({ identifiers: [] }),
      find: jest.fn().mockResolvedValue([]),
      findOne: jest.fn().mockResolvedValue(null),
      query: jest.fn().mockResolvedValue([[], 0]),
    };
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        DevicesService,
        { provide: getRepositoryToken(Device), useValue: repo },
      ],
    }).compile();
    service = module.get(DevicesService);
    warnSpy = jest
      .spyOn(Logger.prototype, 'warn')
      .mockImplementation(() => undefined);
  });

  afterEach(() => warnSpy.mockRestore());

  it('creates the row on first sight and marks device 1 primary', async () => {
    await service.touch(7);

    expect(repo.insert).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: 7,
        deviceId: 1,
        isPrimary: true,
        lastSeenAt: expect.any(Date) as unknown,
      }),
    );
  });

  it('never creates a row for a linked device id (amendment (b))', async () => {
    // Rows for ids >= 2 are created SOLELY by the provisioning commit
    // transaction: an auto-insert here would activate a deviceId no
    // ceremony ever committed. The connect still refreshes lastSeenAt.
    await service.touch(7, 2);

    expect(repo.update).toHaveBeenCalledWith(
      { userId: 7, deviceId: 2 },
      { lastSeenAt: expect.any(Date) as unknown },
    );
    expect(repo.insert).not.toHaveBeenCalled();
  });

  it('a provisioned device row still gets its lastSeenAt refresh', async () => {
    repo.update.mockResolvedValue({ affected: 1 });

    await service.touch(7, 2);

    expect(repo.update).toHaveBeenCalledTimes(1);
    expect(repo.insert).not.toHaveBeenCalled();
  });

  it('an existing row is only touched, never re-primaried or re-platformed', async () => {
    // Rewriting isPrimary on every connect would undo a primary handover the
    // moment the new primary reconnects, and rewriting platform would erase
    // what the row already knows.
    repo.update.mockResolvedValue({ affected: 1 });

    await service.touch(7, 1, 'android');

    expect(repo.update).toHaveBeenCalledWith(
      { userId: 7, deviceId: 1 },
      { lastSeenAt: expect.any(Date) as unknown },
    );
    expect(repo.insert).not.toHaveBeenCalled();
  });

  it('a write failure costs a lastSeenAt, never the connection', async () => {
    repo.update.mockRejectedValue(new Error('db down'));

    await expect(service.touch(7)).resolves.toBeUndefined();
    expect(warnSpy).toHaveBeenCalledTimes(1);
  });

  describe('isActive', () => {
    // Gate for per-device key-material uploads (spec §5.1 / amendment (b)).
    it('false when no row exists (never activated)', async () => {
      await expect(service.isActive(7, 2)).resolves.toBe(false);
      expect(repo.findOne).toHaveBeenCalledWith({
        where: { userId: 7, deviceId: 2 },
      });
    });

    it('true for a live provisioned row', async () => {
      repo.findOne.mockResolvedValue({
        userId: 7,
        deviceId: 2,
        revokedAt: null,
      });
      await expect(service.isActive(7, 2)).resolves.toBe(true);
    });

    it('false for a revoked row', async () => {
      repo.findOne.mockResolvedValue({
        userId: 7,
        deviceId: 2,
        revokedAt: new Date(),
      });
      await expect(service.isActive(7, 2)).resolves.toBe(false);
    });
  });

  describe('isRevoked — the SESSION gate (amendment (xxii))', () => {
    it('false when NO row exists, so legacy accounts are never locked out', async () => {
      // Deliberately the inverse of isActive: every pre-Phase-1 account has no
      // devices row until its first connect writes one (§8), so denying a
      // session on absence would lock out the entire legacy install base.
      await expect(service.isRevoked(7, 1)).resolves.toBe(false);
    });

    it('false for a live row', async () => {
      repo.findOne.mockResolvedValue({
        userId: 7,
        deviceId: 2,
        revokedAt: null,
      });
      await expect(service.isRevoked(7, 2)).resolves.toBe(false);
    });

    it('true ONLY for an explicitly revoked row', async () => {
      repo.findOne.mockResolvedValue({
        userId: 7,
        deviceId: 2,
        revokedAt: new Date(),
      });
      await expect(service.isRevoked(7, 2)).resolves.toBe(true);
    });
  });

  describe('revoke / revokeAllExcept (§5.5, amendment (xxviii))', () => {
    /** Chainable stand-in for the query builder, capturing every clause. */
    const builder = (result: { affected?: number; raw?: unknown }) => {
      const calls: Array<[string, unknown]> = [];
      const chain: Record<string, jest.Mock> = {
        update: jest.fn(() => chain),
        set: jest.fn((patch: unknown) => {
          calls.push(['set', patch]);
          return chain;
        }),
        where: jest.fn((clause: string, params: unknown) => {
          calls.push([clause, params]);
          return chain;
        }),
        andWhere: jest.fn((clause: string, params: unknown) => {
          calls.push([clause, params]);
          return chain;
        }),
        returning: jest.fn((clause: string) => {
          calls.push(['returning', clause]);
          return chain;
        }),
        execute: jest.fn().mockResolvedValue(result),
      };
      return { chain, calls };
    };

    it('reports true when a live row was stamped', async () => {
      const { chain, calls } = builder({ affected: 1 });
      repo.createQueryBuilder = jest.fn(() => chain);

      await expect(service.revoke(7, 2)).resolves.toBe(true);
      // The IS NULL predicate is what serializes two racing revocations.
      expect(calls.map(([clause]) => clause)).toContain('"revokedAt" IS NULL');
    });

    it('reports false when the device was ALREADY revoked (idempotent, no re-teardown)', async () => {
      const { chain } = builder({ affected: 0 });
      repo.createQueryBuilder = jest.fn(() => chain);

      await expect(service.revoke(7, 2)).resolves.toBe(false);
    });

    it('revokeAllExcept returns the ids it stamped, from RETURNING', async () => {
      const { chain, calls } = builder({
        raw: [{ deviceId: 1 }, { deviceId: 2 }],
      });
      repo.createQueryBuilder = jest.fn(() => chain);

      await expect(service.revokeAllExcept(7, 4)).resolves.toEqual([1, 2]);
      // Authoritative set, not a re-read: a concurrent revoke between UPDATE
      // and a follow-up SELECT would hide a device from the teardown.
      expect(calls).toEqual(
        expect.arrayContaining([['returning', '"deviceId"']]),
      );
      expect(calls.map(([clause]) => clause)).toContain(
        '"deviceId" != :keepDeviceId',
      );
    });

    it('revokeAllExcept answers an empty list when nothing was live', async () => {
      const { chain } = builder({ raw: [] });
      repo.createQueryBuilder = jest.fn(() => chain);

      await expect(service.revokeAllExcept(7, 1)).resolves.toEqual([]);
    });
  });

  describe('allocateDeviceId', () => {
    // Real Postgres shape for UPDATE ... RETURNING: [rows, rowCount].
    const returning = (allocatedId: number) => [[{ allocatedId }], 1];

    it('returns the PRE-increment value (first allocation on a fresh column is 2)', async () => {
      // The column starts at 2 (migration 0016 default: every existing
      // account is single-device device 1), so the first allocated id IS 2 —
      // decision record F4's off-by-one rider.
      repo.query.mockResolvedValue(returning(2));

      await expect(service.allocateDeviceId(7)).resolves.toBe(2);
    });

    it('two sequential allocations return N then N+1', async () => {
      repo.query
        .mockResolvedValueOnce(returning(2))
        .mockResolvedValueOnce(returning(3));

      await expect(service.allocateDeviceId(7)).resolves.toBe(2);
      await expect(service.allocateDeviceId(7)).resolves.toBe(3);
    });

    it('throws when the user does not exist (0 rows updated)', async () => {
      repo.query.mockResolvedValue([[], 0]);

      await expect(service.allocateDeviceId(999)).rejects.toThrow(
        /user.*999.*not found|not found.*999/i,
      );
    });

    it('allocates in ONE atomic UPDATE ... RETURNING statement', async () => {
      // The whole point of the allocator (spec §12 Stage-0 amendment (a)) is
      // that concurrent allocations serialize on the row lock of a single
      // statement — a read-then-write would hand two ceremonies the same id.
      repo.query.mockResolvedValue(returning(2));

      await service.allocateDeviceId(7);

      expect(repo.query).toHaveBeenCalledTimes(1);
      const [sql, params] = repo.query.mock.calls[0] as [string, unknown[]];
      expect(sql).toContain('UPDATE');
      expect(sql).toContain('"nextDeviceId" + 1');
      expect(sql).toContain('RETURNING');
      expect(sql).toContain('"nextDeviceId" - 1');
      expect(sql).not.toContain('SELECT'); // no read-then-write
      expect(params).toEqual([7]);
    });
  });
});
