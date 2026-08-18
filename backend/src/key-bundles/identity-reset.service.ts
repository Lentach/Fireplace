import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, Repository } from 'typeorm';
import * as argon2 from 'argon2';
import { IdentityResetRequest } from './identity-reset-request.entity';
import { RecoveryKey } from './recovery-key.entity';

/**
 * Delay before a reset may replace the account identity. Long by design: push
 * is this app's only offline channel (no email), so the window has to survive
 * a phone being face-down overnight. Owner-confirmed at 72 h.
 */
export const RESET_DELAY_MS = 72 * 60 * 60 * 1000;

/**
 * Delay when a valid recovery key is presented. Shortens the wait; it never
 * removes the notifications or the ability to cancel (§6.2.1).
 */
export const RESET_DELAY_RECOVERY_MS = 60 * 60 * 1000;

/** Quiet period after a cancel, so a refused attempt cannot be retried in a loop. */
export const CANCEL_COOLDOWN_MS = 24 * 60 * 60 * 1000;

/**
 * How long a COMPLETED ceremony stays spendable.
 *
 * Without this bound a completed ceremony is a standing authorization: the
 * delay has already elapsed, so the replacement it permits is instant, and
 * `cancelReset` cannot touch it (that only acts on a pending row). An account
 * whose owner recovered their device and simply stopped would keep an
 * indefinite, un-cancellable instant-replacement grant — the exact "zero-delay
 * path" §6.2.1 rules out. Bounded, an unused grant lapses and a fresh ceremony
 * (with its full delay and notifications) is required again; starting one is
 * not blocked, since the cooldown applies only after a CANCEL.
 */
export const COMPLETED_GRANT_TTL_MS = 24 * 60 * 60 * 1000;

export const RECOVERY_MAX_FAILED_ATTEMPTS = 5;
export const RECOVERY_LOCKOUT_MS = 60 * 60 * 1000;

/**
 * Argon2id parameters for the recovery-key verifier. Memory-hard on purpose:
 * a database dump must not turn into an offline guessing exercise. Values are
 * the current OWASP Password Storage profile (19 MiB, 2 iterations, 1 lane).
 * Raising these stays compatible (the PHC string self-describes, so existing
 * hashes keep verifying); dropping below OWASP guidance does not.
 */
export const RECOVERY_ARGON2_OPTIONS: argon2.HashOptions = {
  type: argon2.argon2id,
  memoryCost: 19456,
  timeCost: 2,
  parallelism: 1,
};

export type RequestResetStatus =
  'pending' | 'existing' | 'cooldown' | 'invalid_phrase' | 'locked';

export interface RequestResetResult {
  status: RequestResetStatus;
  deadlineAt: Date | null;
  shortened: boolean;
}

export interface IdentityResetStatusSummary {
  status: 'pending' | 'completed';
  deadlineAt: Date;
}

/**
 * Internal: the partial unique index refused a second pending row because a
 * concurrent request won the race.
 *
 * Thrown so the transaction ROLLS BACK. The loser may have presented a valid
 * recovery phrase, and that phrase is single-use: committing here would spend
 * it on a ceremony it did not create, leaving the account on the winner's
 * un-shortened 72 h deadline with no phrase left to shorten a retry.
 */
class PendingResetConflict extends Error {
  constructor(readonly insertError: unknown) {
    super('a pending reset already exists for this account');
    this.name = 'PendingResetConflict';
  }
}

/**
 * The account-identity reset ceremony (Phase 0b, multi-device spec §6.2) and
 * its optional recovery key (§6.2.1).
 *
 * This service owns ceremony STATE only — notifications are fanned out by the
 * socket layer, which holds the room and push plumbing. All state lives in
 * Postgres because every timing decision must survive a container restart.
 */
@Injectable()
export class IdentityResetService {
  private readonly logger = new Logger(IdentityResetService.name);

  constructor(
    @InjectRepository(IdentityResetRequest)
    private readonly resetRepo: Repository<IdentityResetRequest>,
    @InjectRepository(RecoveryKey)
    private readonly recoveryRepo: Repository<RecoveryKey>,
    private readonly dataSource: DataSource,
  ) {}

  /**
   * Starts a ceremony, or reports why it was not started.
   *
   * A phrase presentation and the resulting row commit together: a phrase can
   * never be spent without producing the ceremony it paid for, and a shortened
   * ceremony can never exist without the phrase having been spent.
   */
  async requestReset(
    userId: number,
    recoveryPhrase?: string,
  ): Promise<RequestResetResult> {
    const existing = await this.resetRepo.findOne({
      where: { userId, status: 'pending' },
    });
    if (existing) {
      return {
        status: 'existing',
        deadlineAt: existing.deadlineAt,
        shortened: existing.shortened,
      };
    }

    const recentCancel = await this.resetRepo
      .createQueryBuilder('r')
      .where('r."userId" = :userId', { userId })
      .andWhere('r.status = :status', { status: 'cancelled' })
      .andWhere('r."cancelledAt" > :since', {
        since: new Date(Date.now() - CANCEL_COOLDOWN_MS),
      })
      .orderBy('r."cancelledAt"', 'DESC')
      .getOne();
    if (recentCancel) {
      return { status: 'cooldown', deadlineAt: null, shortened: false };
    }

    try {
      return await this.dataSource.transaction(async (manager) => {
        let shortened = false;
        if (recoveryPhrase != null && recoveryPhrase.length > 0) {
          const outcome = await this.spendRecoveryPhrase(
            manager.getRepository(RecoveryKey),
            userId,
            recoveryPhrase,
          );
          if (outcome !== 'accepted') {
            return { status: outcome, deadlineAt: null, shortened: false };
          }
          shortened = true;
        }

        const deadlineAt = new Date(
          Date.now() + (shortened ? RESET_DELAY_RECOVERY_MS : RESET_DELAY_MS),
        );
        try {
          await manager.getRepository(IdentityResetRequest).insert({
            userId,
            status: 'pending',
            deadlineAt,
            shortened,
          });
        } catch (error) {
          // Leave the transaction by throwing: the winner's row is not visible
          // to this one anyway, and rolling back is what un-spends a recovery
          // phrase this request paid but got no ceremony for.
          throw new PendingResetConflict(error);
        }
        this.logger.warn(
          `[identity-reset] ceremony started userId=${userId} shortened=${shortened} deadlineAt=${deadlineAt.toISOString()}`,
        );
        return { status: 'pending' as const, deadlineAt, shortened };
      });
    } catch (error) {
      if (!(error instanceof PendingResetConflict)) throw error;
      // Read the winner AFTER the rollback, on a fresh transaction: report its
      // deadline rather than inventing one.
      const winner = await this.resetRepo.findOne({
        where: { userId, status: 'pending' },
      });
      if (winner) {
        return {
          status: 'existing',
          deadlineAt: winner.deadlineAt,
          shortened: winner.shortened,
        };
      }
      // No winner: the insert failed for some other reason (or the race winner
      // was cancelled in between). Nothing was spent, so surface the fault.
      throw error.insertError;
    }
  }

  /**
   * Verifies and spends a recovery phrase, returning 'accepted' or the status
   * explaining the refusal. Failures are counted and trigger a lockout, so the
   * phrase cannot be guessed online.
   */
  private async spendRecoveryPhrase(
    recoveryRepo: Repository<RecoveryKey>,
    userId: number,
    phrase: string,
  ): Promise<'accepted' | 'invalid_phrase' | 'locked'> {
    const row = await recoveryRepo.findOne({ where: { userId } });
    // No phrase enrolled, or already spent: the caller gets the same answer
    // either way — neither response should reveal whether an account has one.
    if (!row || row.usedAt != null) return 'invalid_phrase';
    if (row.lockedUntil != null && row.lockedUntil.getTime() > Date.now()) {
      return 'locked';
    }

    const valid = await argon2
      .verify(row.verifierHash, phrase)
      .catch((error: unknown) => {
        // A malformed stored hash must never authorize anything.
        this.logger.error(
          `[identity-reset] recovery verify failed userId=${userId}: ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
        return false;
      });

    if (!valid) {
      // Counted in SQL, not read-modify-write: two failures landing together
      // would otherwise both read the same count and both store count+1,
      // quietly buying extra attempts before the lockout.
      const updated = await recoveryRepo
        .createQueryBuilder()
        .update(RecoveryKey)
        .set({
          failedAttempts: () => '"failedAttempts" + 1',
          lockedUntil: () =>
            `CASE WHEN "failedAttempts" + 1 >= ${RECOVERY_MAX_FAILED_ATTEMPTS}` +
            ` THEN :lockedUntil ELSE "lockedUntil" END`,
        })
        .where('id = :id', {
          id: row.id,
          lockedUntil: new Date(Date.now() + RECOVERY_LOCKOUT_MS),
        })
        .returning(['failedAttempts'])
        .execute();
      const stored = (updated.raw as Array<{ failedAttempts?: number }>)[0]
        ?.failedAttempts;
      const failedAttempts = Number(stored ?? row.failedAttempts + 1);
      return failedAttempts >= RECOVERY_MAX_FAILED_ATTEMPTS
        ? 'locked'
        : 'invalid_phrase';
    }

    // Single-use: spent in the same transaction that creates the ceremony.
    await recoveryRepo.update(
      { id: row.id },
      { usedAt: new Date(), failedAttempts: 0, lockedUntil: null },
    );
    return 'accepted';
  }

  /**
   * Cancels the pending ceremony. Conditional on status='pending', which is
   * what serializes a cancel against the expiry commit: if the commit already
   * landed, this affects no rows and the completed reset stands.
   */
  async cancelReset(userId: number): Promise<boolean> {
    const result = await this.resetRepo
      .createQueryBuilder()
      .update(IdentityResetRequest)
      .set({ status: 'cancelled', cancelledAt: () => 'now()' })
      .where('"userId" = :userId', { userId })
      .andWhere('status = :status', { status: 'pending' })
      .execute();
    const cancelled = (result.affected ?? 0) > 0;
    if (cancelled) {
      this.logger.warn(`[identity-reset] ceremony cancelled userId=${userId}`);
    }
    return cancelled;
  }

  /**
   * Spends a completed ceremony to authorize exactly one identity replacement.
   * Conditional on consumedAt IS NULL, so two concurrent uploads can never both
   * be authorized by the same ceremony.
   */
  async consumeCompletedReset(userId: number): Promise<boolean> {
    const result = await this.resetRepo
      .createQueryBuilder()
      .update(IdentityResetRequest)
      .set({ consumedAt: () => 'now()' })
      .where('"userId" = :userId', { userId })
      .andWhere('status = :status', { status: 'completed' })
      .andWhere('"consumedAt" IS NULL')
      .andWhere('"completedAt" > :graceSince', {
        graceSince: new Date(Date.now() - COMPLETED_GRANT_TTL_MS),
      })
      .execute();
    const consumed = (result.affected ?? 0) > 0;
    if (consumed) {
      this.logger.warn(
        `[identity-reset] completed ceremony consumed by identity upload userId=${userId}`,
      );
    }
    return consumed;
  }

  /**
   * What a client needs to render its own state at connect time: a pending
   * ceremony with its deadline, or an unspent completed one.
   */
  async getStatusForUser(
    userId: number,
  ): Promise<IdentityResetStatusSummary | null> {
    const pending = await this.resetRepo.findOne({
      where: { userId, status: 'pending' },
    });
    if (pending) {
      return { status: 'pending', deadlineAt: pending.deadlineAt };
    }
    const completed = await this.resetRepo
      .createQueryBuilder('r')
      .where('r."userId" = :userId', { userId })
      .andWhere('r.status = :status', { status: 'completed' })
      .andWhere('r."consumedAt" IS NULL')
      .andWhere('r."completedAt" > :graceSince', {
        graceSince: new Date(Date.now() - COMPLETED_GRANT_TTL_MS),
      })
      .orderBy('r."completedAt"', 'DESC')
      .getOne();
    if (completed) {
      return { status: 'completed', deadlineAt: completed.deadlineAt };
    }
    return null;
  }

  /**
   * Enrolls or replaces the account's recovery phrase. Only the Argon2id
   * verifier is stored. Replacing clears the spent/lockout state, because the
   * new phrase is a new secret.
   */
  async setRecoveryKey(userId: number, phrase: string): Promise<void> {
    const verifierHash = await argon2.hash(phrase, RECOVERY_ARGON2_OPTIONS);
    const existing = await this.recoveryRepo.findOne({ where: { userId } });
    if (existing) {
      await this.recoveryRepo.update(
        { id: existing.id },
        { verifierHash, usedAt: null, failedAttempts: 0, lockedUntil: null },
      );
      return;
    }
    await this.recoveryRepo.insert({ userId, verifierHash });
  }

  /**
   * Commits ceremonies whose delay has elapsed. Runs every minute so a restart
   * cannot skip a deadline.
   *
   * The status='pending' predicate in the UPDATE is the serialization point
   * against a concurrent cancel — no row is ever pulled back out of a terminal
   * state. Completion also invalidates any unspent recovery phrase in the same
   * transaction (§6.2.1: a completed reset spends it too).
   *
   * Completion deliberately fans out NO notification: the loud surface fires
   * when the new identity key is actually uploaded, through the existing
   * identity-replacement alarm.
   */
  @Cron(CronExpression.EVERY_MINUTE)
  async completeDueResets(): Promise<void> {
    try {
      await this.dataSource.transaction(async (manager) => {
        const result = await manager
          .getRepository(IdentityResetRequest)
          .createQueryBuilder()
          .update(IdentityResetRequest)
          .set({ status: 'completed', completedAt: () => 'now()' })
          .where('status = :status', { status: 'pending' })
          .andWhere('"deadlineAt" <= now()')
          .returning('"id", "userId"')
          .execute();
        const raw: unknown = result.raw;
        const rows: Array<{ userId: number }> = Array.isArray(raw)
          ? (raw as Array<{ userId: number }>)
          : [];
        if (rows.length === 0) return;
        const userIds = [...new Set(rows.map((row) => row.userId))];
        await manager
          .getRepository(RecoveryKey)
          .createQueryBuilder()
          .update(RecoveryKey)
          .set({ usedAt: () => 'now()' })
          .where('"userId" IN (:...userIds)', { userIds })
          .andWhere('"usedAt" IS NULL')
          .execute();
        for (const userId of userIds) {
          this.logger.warn(
            `[identity-reset] delay elapsed, identity replacement authorized userId=${userId}`,
          );
        }
      });
    } catch (error) {
      // A failed sweep must never kill the scheduler; the next minute retries.
      this.logger.error(
        `[identity-reset] expiry sweep failed: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }
}
