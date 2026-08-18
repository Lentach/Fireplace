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
      upsert: jest.fn().mockResolvedValue({ identifiers: [] }),
      find: jest.fn().mockResolvedValue([]),
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

    expect(repo.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: 7,
        deviceId: 1,
        isPrimary: true,
        lastSeenAt: expect.any(Date) as unknown,
      }),
      { conflictPaths: ['userId', 'deviceId'] },
    );
  });

  it('never marks a linked device primary', async () => {
    // Invariant I2: only a Keystore-capable device may be primary, and the
    // primary is the account's original device until §6.3 hands it over.
    await service.touch(7, 2);

    expect(repo.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ deviceId: 2, isPrimary: false }),
      expect.anything(),
    );
  });

  it('a write failure costs a lastSeenAt, never the connection', async () => {
    repo.upsert.mockRejectedValue(new Error('db down'));

    await expect(service.touch(7)).resolves.toBeUndefined();
    expect(warnSpy).toHaveBeenCalledTimes(1);
  });
});
