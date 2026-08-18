import { Logger } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import * as argon2 from 'argon2';
import {
  CANCEL_COOLDOWN_MS,
  COMPLETED_GRANT_TTL_MS,
  IdentityResetService,
  RECOVERY_ARGON2_OPTIONS,
  RECOVERY_MAX_FAILED_ATTEMPTS,
  RESET_DELAY_MS,
  RESET_DELAY_RECOVERY_MS,
} from './identity-reset.service';
import { IdentityResetRequest } from './identity-reset-request.entity';
import { RecoveryKey } from './recovery-key.entity';

interface BuilderMock {
  update: jest.Mock;
  set: jest.Mock;
  where: jest.Mock;
  andWhere: jest.Mock;
  orderBy: jest.Mock;
  returning: jest.Mock;
  execute: jest.Mock;
  getOne: jest.Mock;
}

/** A query-builder call: SQL fragment plus optional bound parameters. */
type QueryCall = [string, Record<string, unknown>?];

/**
 * Chainable stand-in covering both shapes the service builds: SELECT chains
 * ending in getOne(), and UPDATE chains ending in execute().
 */
function makeBuilder(result: {
  affected?: number;
  raw?: unknown;
  one?: unknown;
}): BuilderMock {
  const builder = {
    update: jest.fn(),
    set: jest.fn(),
    where: jest.fn(),
    andWhere: jest.fn(),
    orderBy: jest.fn(),
    returning: jest.fn(),
    execute: jest.fn().mockResolvedValue({
      affected: result.affected ?? 0,
      raw: result.raw ?? [],
    }),
    getOne: jest.fn().mockResolvedValue(result.one ?? null),
  };
  builder.update.mockReturnValue(builder);
  builder.set.mockReturnValue(builder);
  builder.where.mockReturnValue(builder);
  builder.andWhere.mockReturnValue(builder);
  builder.orderBy.mockReturnValue(builder);
  builder.returning.mockReturnValue(builder);
  return builder;
}

/** Bound parameters of the first call that binds `key`, if any. */
function boundParams(
  mock: jest.Mock,
  key: string,
): Record<string, unknown> | undefined {
  const calls = mock.mock.calls as QueryCall[];
  return calls.find((call) => call[1] != null && key in call[1])?.[1];
}

/** Bound parameters of the first call whose params satisfy `predicate`. */
function boundParamsWhere(
  mock: jest.Mock,
  predicate: (params: Record<string, unknown>) => boolean,
): Record<string, unknown> | undefined {
  const calls = mock.mock.calls as QueryCall[];
  return calls.find((call) => call[1] != null && predicate(call[1]))?.[1];
}

/** Every SQL fragment passed to a builder method. */
function sqlFragments(mock: jest.Mock): string[] {
  const calls = mock.mock.calls as QueryCall[];
  return calls.map((call) => String(call[0]));
}

/**
 * SQL produced by an UPDATE ... SET object. Values are either literals or
 * functions returning a raw fragment; only the fragments are of interest.
 */
function setSql(mock: jest.Mock): string {
  const calls = mock.mock.calls as Array<[Record<string, unknown>]>;
  return calls
    .flatMap((call) => Object.values(call[0] ?? {}))
    .map((value) =>
      typeof value === 'function' ? (value as () => string)() : '',
    )
    .join(' ');
}

/** The row object handed to a repository insert/update call. */
function rowArg(mock: jest.Mock, callIndex = 0): Record<string, unknown> {
  const calls = mock.mock.calls as Array<[Record<string, unknown>]>;
  return calls[callIndex][0];
}

describe('IdentityResetService (reset ceremony §6.2 / recovery key §6.2.1)', () => {
  let service: IdentityResetService;
  let resetRepo: Record<string, jest.Mock>;
  let recoveryRepo: Record<string, jest.Mock>;
  let resetBuilder: BuilderMock;
  let recoveryBuilder: BuilderMock;
  let warnSpy: jest.SpyInstance;
  // Errors that escaped the transaction callback — a real transaction ROLLS
  // BACK on each of these, undoing anything it wrote (a spent phrase above
  // all).
  let rolledBack: unknown[];

  beforeEach(async () => {
    rolledBack = [];
    resetBuilder = makeBuilder({ affected: 0 });
    recoveryBuilder = makeBuilder({ affected: 0 });
    resetRepo = {
      findOne: jest.fn().mockResolvedValue(null),
      insert: jest.fn().mockResolvedValue({ identifiers: [{ id: 1 }] }),
      createQueryBuilder: jest.fn(() => resetBuilder),
    };
    recoveryRepo = {
      findOne: jest.fn().mockResolvedValue(null),
      insert: jest.fn().mockResolvedValue({ identifiers: [{ id: 1 }] }),
      update: jest.fn().mockResolvedValue({ affected: 1 }),
      createQueryBuilder: jest.fn(() => recoveryBuilder),
    };

    // The service spends the phrase and creates the row inside ONE
    // transaction; the manager hands back the same mocks.
    const manager = {
      getRepository: jest.fn((entity: unknown) =>
        entity === RecoveryKey ? recoveryRepo : resetRepo,
      ),
    };
    const dataSource = {
      transaction: jest.fn(async (cb: (m: unknown) => unknown) => {
        try {
          return await cb(manager);
        } catch (error) {
          rolledBack.push(error);
          throw error;
        }
      }),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        IdentityResetService,
        {
          provide: getRepositoryToken(IdentityResetRequest),
          useValue: resetRepo,
        },
        { provide: getRepositoryToken(RecoveryKey), useValue: recoveryRepo },
        { provide: DataSource, useValue: dataSource },
      ],
    }).compile();

    service = module.get(IdentityResetService);
    warnSpy = jest
      .spyOn(Logger.prototype, 'warn')
      .mockImplementation(() => undefined);
  });

  afterEach(() => {
    warnSpy.mockRestore();
    jest.clearAllMocks();
  });

  describe('requestReset', () => {
    it('starts a ceremony with the full delay when nothing is pending', async () => {
      const before = Date.now();
      const result = await service.requestReset(7);

      expect(result.status).toBe('pending');
      expect(result.shortened).toBe(false);
      const deadline = result.deadlineAt?.getTime() ?? 0;
      expect(deadline).toBeGreaterThanOrEqual(before + RESET_DELAY_MS - 5000);
      expect(deadline).toBeLessThanOrEqual(Date.now() + RESET_DELAY_MS + 5000);
      expect(resetRepo.insert).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 7,
          status: 'pending',
          shortened: false,
        }),
      );
    });

    it('is a no-op returning the existing deadline while one is pending', async () => {
      const deadlineAt = new Date(Date.now() + 1000);
      resetRepo.findOne.mockResolvedValue({
        userId: 7,
        status: 'pending',
        deadlineAt,
        shortened: false,
      });

      const result = await service.requestReset(7);

      expect(result).toEqual({
        status: 'existing',
        deadlineAt,
        shortened: false,
      });
      // A repeat request must not restart or extend the clock.
      expect(resetRepo.insert).not.toHaveBeenCalled();
    });

    it('refuses during the cooldown that follows a cancel', async () => {
      resetBuilder.getOne.mockResolvedValue({
        userId: 7,
        status: 'cancelled',
        cancelledAt: new Date(Date.now() - 1000),
      });

      const result = await service.requestReset(7);

      expect(result.status).toBe('cooldown');
      expect(resetRepo.insert).not.toHaveBeenCalled();
    });

    it('queries the cooldown window against the documented 24 h bound', async () => {
      await service.requestReset(7);

      const params = boundParams(resetBuilder.andWhere, 'since');
      expect(params).toBeDefined();
      const since = params?.since as Date;
      expect(Date.now() - since.getTime()).toBeGreaterThanOrEqual(
        CANCEL_COOLDOWN_MS - 5000,
      );
    });

    describe('with a recovery phrase', () => {
      const phrase =
        'abandon ability able about above absent absorb abstract absurd abuse access accident';
      let verifierHash: string;

      beforeAll(async () => {
        verifierHash = await argon2.hash(phrase, RECOVERY_ARGON2_OPTIONS);
      });

      const enrolled = (overrides: Record<string, unknown> = {}) => ({
        id: 3,
        userId: 7,
        verifierHash,
        usedAt: null,
        failedAttempts: 0,
        lockedUntil: null,
        ...overrides,
      });

      it('shortens the delay to one hour and spends the phrase', async () => {
        recoveryRepo.findOne.mockResolvedValue(enrolled());

        const result = await service.requestReset(7, phrase);

        expect(result.status).toBe('pending');
        expect(result.shortened).toBe(true);
        const remaining = (result.deadlineAt?.getTime() ?? 0) - Date.now();
        expect(remaining).toBeLessThanOrEqual(RESET_DELAY_RECOVERY_MS + 5000);
        expect(remaining).toBeGreaterThan(RESET_DELAY_RECOVERY_MS - 5000);
        // Single-use: spent in the same transaction that created the ceremony.
        expect(recoveryRepo.update).toHaveBeenCalledWith(
          { id: 3 },
          expect.objectContaining({ usedAt: expect.any(Date) as unknown }),
        );
        expect(resetRepo.insert).toHaveBeenCalledWith(
          expect.objectContaining({ shortened: true }),
        );
      });

      it('rolls the phrase spend back when a concurrent request wins the race', async () => {
        recoveryRepo.findOne.mockResolvedValue(enrolled());
        // The partial unique index refuses the second pending row...
        resetRepo.insert.mockRejectedValue(
          new Error('duplicate key value violates unique constraint'),
        );
        const winnerDeadline = new Date(Date.now() + RESET_DELAY_MS);
        // ...and the winner is read back after the rollback, on this.resetRepo.
        resetRepo.findOne
          .mockResolvedValueOnce(null)
          .mockResolvedValue({ deadlineAt: winnerDeadline, shortened: false });

        const result = await service.requestReset(7, phrase);

        // The loser reports the winner's ceremony, not one of its own.
        expect(result.status).toBe('existing');
        expect(result.deadlineAt).toEqual(winnerDeadline);
        expect(result.shortened).toBe(false);
        // And the transaction was rolled back, so the single-use phrase is NOT
        // spent: committing here would leave the account on the winner's 72 h
        // deadline with nothing left to shorten a retry.
        expect(rolledBack).toHaveLength(1);
      });

      it('refuses a wrong phrase, counts it, and creates no ceremony', async () => {
        recoveryRepo.findOne.mockResolvedValue(enrolled({ failedAttempts: 1 }));
        recoveryBuilder.execute.mockResolvedValue({
          affected: 1,
          raw: [{ failedAttempts: 2 }],
        });

        const result = await service.requestReset(7, 'not the right phrase');

        expect(result.status).toBe('invalid_phrase');
        expect(resetRepo.insert).not.toHaveBeenCalled();
        // Counted by the database, not by a read-modify-write: two failures
        // landing together must not both store the same count.
        expect(setSql(recoveryBuilder.set)).toContain('"failedAttempts" + 1');
        expect(recoveryRepo.update).not.toHaveBeenCalled();
      });

      it('locks out on the attempt whose stored count reaches the limit', async () => {
        recoveryRepo.findOne.mockResolvedValue(
          enrolled({ failedAttempts: RECOVERY_MAX_FAILED_ATTEMPTS - 1 }),
        );
        // The lockout follows the value the UPDATE actually stored, so a
        // concurrent failure that already advanced the counter still locks.
        recoveryBuilder.execute.mockResolvedValue({
          affected: 1,
          raw: [{ failedAttempts: RECOVERY_MAX_FAILED_ATTEMPTS }],
        });

        const result = await service.requestReset(7, 'wrong again');

        expect(result.status).toBe('locked');
        const params = boundParams(recoveryBuilder.where, 'lockedUntil');
        expect(params?.lockedUntil).toBeInstanceOf(Date);
        // The threshold is applied in SQL against the row's own value.
        expect(setSql(recoveryBuilder.set)).toContain(
          `"failedAttempts" + 1 >= ${RECOVERY_MAX_FAILED_ATTEMPTS}`,
        );
      });

      it('refuses while locked, without even checking the phrase', async () => {
        recoveryRepo.findOne.mockResolvedValue(
          enrolled({
            failedAttempts: RECOVERY_MAX_FAILED_ATTEMPTS,
            lockedUntil: new Date(Date.now() + 60_000),
          }),
        );

        const result = await service.requestReset(7, phrase);

        expect(result.status).toBe('locked');
        expect(resetRepo.insert).not.toHaveBeenCalled();
        expect(recoveryRepo.update).not.toHaveBeenCalled();
      });

      it('refuses an already-spent phrase', async () => {
        recoveryRepo.findOne.mockResolvedValue(
          enrolled({ usedAt: new Date() }),
        );

        const result = await service.requestReset(7, phrase);

        expect(result.status).toBe('invalid_phrase');
        expect(resetRepo.insert).not.toHaveBeenCalled();
      });

      it('refuses when no phrase is enrolled at all', async () => {
        recoveryRepo.findOne.mockResolvedValue(null);

        const result = await service.requestReset(7, phrase);

        expect(result.status).toBe('invalid_phrase');
        expect(resetRepo.insert).not.toHaveBeenCalled();
      });

      it('never authorizes anything when the stored verifier is malformed', async () => {
        const errorSpy = jest
          .spyOn(Logger.prototype, 'error')
          .mockImplementation(() => undefined);
        recoveryRepo.findOne.mockResolvedValue(
          enrolled({ verifierHash: 'not-a-phc-string' }),
        );

        const result = await service.requestReset(7, phrase);

        expect(result.status).toBe('invalid_phrase');
        expect(resetRepo.insert).not.toHaveBeenCalled();
        errorSpy.mockRestore();
      });
    });
  });

  describe('cancel / expiry serialization (falsification 10)', () => {
    it('cancels only a row that is still pending', async () => {
      resetBuilder.execute.mockResolvedValue({ affected: 1, raw: [] });

      await expect(service.cancelReset(7)).resolves.toBe(true);

      expect(
        boundParamsWhere(
          resetBuilder.andWhere,
          (params) => params.status === 'pending',
        ),
      ).toBeDefined();
    });

    it('reports no cancellation when the ceremony already left pending', async () => {
      // The expiry commit won the race: nothing to cancel, and emphatically no
      // rollback of the completed state.
      resetBuilder.execute.mockResolvedValue({ affected: 0, raw: [] });

      await expect(service.cancelReset(7)).resolves.toBe(false);
    });

    it('commits only passed deadlines, still filtered on pending', async () => {
      resetBuilder.execute.mockResolvedValue({
        affected: 1,
        raw: [{ id: 5, userId: 7 }],
      });

      await service.completeDueResets();

      expect(
        boundParamsWhere(
          resetBuilder.where,
          (params) => params.status === 'pending',
        ),
      ).toBeDefined();
      expect(
        sqlFragments(resetBuilder.andWhere).some((sql) =>
          sql.includes('"deadlineAt" <= now()'),
        ),
      ).toBe(true);
    });

    it('invalidates an unspent recovery phrase when a ceremony completes', async () => {
      resetBuilder.execute.mockResolvedValue({
        affected: 1,
        raw: [{ id: 5, userId: 7 }],
      });

      await service.completeDueResets();

      expect(recoveryBuilder.execute).toHaveBeenCalled();
      expect(
        sqlFragments(recoveryBuilder.andWhere).some((sql) =>
          sql.includes('"usedAt" IS NULL'),
        ),
      ).toBe(true);
    });

    it('does nothing at all when no deadline has passed', async () => {
      resetBuilder.execute.mockResolvedValue({ affected: 0, raw: [] });

      await service.completeDueResets();

      expect(recoveryBuilder.execute).not.toHaveBeenCalled();
    });

    it('survives a failing sweep so the scheduler keeps running', async () => {
      const errorSpy = jest
        .spyOn(Logger.prototype, 'error')
        .mockImplementation(() => undefined);
      resetBuilder.execute.mockRejectedValue(new Error('db down'));

      await expect(service.completeDueResets()).resolves.toBeUndefined();
      expect(errorSpy).toHaveBeenCalled();
      errorSpy.mockRestore();
    });
  });

  describe('consumeCompletedReset', () => {
    it('spends a completed, unconsumed ceremony exactly once', async () => {
      resetBuilder.execute.mockResolvedValue({ affected: 1, raw: [] });

      await expect(service.consumeCompletedReset(7)).resolves.toBe(true);

      expect(
        sqlFragments(resetBuilder.andWhere).some((sql) =>
          sql.includes('"consumedAt" IS NULL'),
        ),
      ).toBe(true);
      expect(
        boundParamsWhere(
          resetBuilder.andWhere,
          (params) => params.status === 'completed',
        ),
      ).toBeDefined();
    });

    it('authorizes nothing when there is no completed ceremony', async () => {
      resetBuilder.execute.mockResolvedValue({ affected: 0, raw: [] });

      await expect(service.consumeCompletedReset(7)).resolves.toBe(false);
    });

    it('only spends a grant inside its bounded window', async () => {
      // A completed ceremony nobody used is an INSTANT replacement grant that
      // cancelReset can no longer touch, so it must lapse rather than stand
      // open forever.
      resetBuilder.execute.mockResolvedValue({ affected: 1, raw: [] });

      await service.consumeCompletedReset(7);

      const params = boundParams(resetBuilder.andWhere, 'graceSince');
      expect(params).toBeDefined();
      expect(
        sqlFragments(resetBuilder.andWhere).some((sql) =>
          sql.includes('"completedAt"'),
        ),
      ).toBe(true);
      const since = params?.graceSince as Date;
      expect(Date.now() - since.getTime()).toBeGreaterThanOrEqual(
        COMPLETED_GRANT_TTL_MS - 5000,
      );
    });

    it('hides a lapsed grant from the connect-time status too', async () => {
      resetRepo.findOne.mockResolvedValue(null);
      resetBuilder.getOne.mockResolvedValue(null);

      await expect(service.getStatusForUser(7)).resolves.toBeNull();

      expect(boundParams(resetBuilder.andWhere, 'graceSince')).toBeDefined();
    });
  });

  describe('getStatusForUser', () => {
    it('reports a pending ceremony with its deadline', async () => {
      const deadlineAt = new Date(Date.now() + 1000);
      resetRepo.findOne.mockResolvedValue({ status: 'pending', deadlineAt });

      await expect(service.getStatusForUser(7)).resolves.toEqual({
        status: 'pending',
        deadlineAt,
      });
    });

    it('reports an unspent completed ceremony', async () => {
      const deadlineAt = new Date(Date.now() - 1000);
      resetBuilder.getOne.mockResolvedValue({
        status: 'completed',
        deadlineAt,
      });

      await expect(service.getStatusForUser(7)).resolves.toEqual({
        status: 'completed',
        deadlineAt,
      });
    });

    it('reports nothing when the account has no ceremony', async () => {
      await expect(service.getStatusForUser(7)).resolves.toBeNull();
    });
  });

  describe('setRecoveryKey (falsification 21)', () => {
    const phrase =
      'legal winner thank year wave sausage worth useful legal winner thank yellow';

    it('stores a memory-hard verifier, never the phrase and never a fast hash', async () => {
      await service.setRecoveryKey(7, phrase);

      const stored = rowArg(recoveryRepo.insert).verifierHash as string;
      // A fast hash (or the phrase itself) fails every one of these.
      expect(stored.startsWith('$argon2id$')).toBe(true);
      expect(stored).not.toContain(phrase);
      expect(await argon2.verify(stored, phrase)).toBe(true);
      expect(await argon2.verify(stored, 'wrong phrase')).toBe(false);
    });

    it('pins the parameters the verifier is stored with', async () => {
      await service.setRecoveryKey(7, phrase);

      const stored = rowArg(recoveryRepo.insert).verifierHash as string;
      // PHC encodes the cost parameters; drifting below them silently weakens
      // every future enrollment, which no behavioural test would notice.
      expect(stored).toContain(`m=${RECOVERY_ARGON2_OPTIONS.memoryCost}`);
      expect(stored).toContain(`t=${RECOVERY_ARGON2_OPTIONS.timeCost}`);
      expect(stored).toContain(`p=${RECOVERY_ARGON2_OPTIONS.parallelism}`);
    });

    it('produces a different verifier each time (salted)', async () => {
      await service.setRecoveryKey(7, phrase);
      await service.setRecoveryKey(7, phrase);

      expect(rowArg(recoveryRepo.insert, 0).verifierHash).not.toEqual(
        rowArg(recoveryRepo.insert, 1).verifierHash,
      );
    });

    it('replacing a phrase clears the spent and lockout state', async () => {
      recoveryRepo.findOne.mockResolvedValue({ id: 3, userId: 7 });

      await service.setRecoveryKey(7, phrase);

      expect(recoveryRepo.update).toHaveBeenCalledWith(
        { id: 3 },
        expect.objectContaining({
          usedAt: null,
          failedAttempts: 0,
          lockedUntil: null,
        }),
      );
      expect(recoveryRepo.insert).not.toHaveBeenCalled();
    });
  });
});
