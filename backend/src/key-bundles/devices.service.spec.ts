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

  it('never marks a linked device primary', async () => {
    // Invariant I2: only a Keystore-capable device may be primary, and the
    // primary is the account's original device until §6.3 hands it over.
    await service.touch(7, 2);

    expect(repo.insert).toHaveBeenCalledWith(
      expect.objectContaining({ deviceId: 2, isPrimary: false }),
    );
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
