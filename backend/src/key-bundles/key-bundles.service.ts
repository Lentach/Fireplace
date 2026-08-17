import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { KeyBundle } from './key-bundle.entity';
import { OneTimePreKey } from './one-time-pre-key.entity';
import { IdentityChangeAudit } from './identity-change-audit.entity';
import { IdentityResetService } from './identity-reset.service';
import { verifyIdentityChangeSignature } from './identity-signature.util';

export interface KeyBundleData {
  registrationId: number;
  identityPublicKey: string;
  signedPreKeyId: number;
  signedPreKeyPublic: string;
  signedPreKeySignature: string;
}

export interface OneTimePreKeyData {
  keyId: number;
  publicKey: string;
}

export interface PreKeyBundleResponse {
  registrationId: number;
  identityPublicKey: string;
  signedPreKeyId: number;
  signedPreKeyPublic: string;
  signedPreKeySignature: string;
  oneTimePreKeyId: number | null;
  oneTimePreKeyPublic: string | null;
}

export interface UpsertKeyBundleResult {
  /** True when the upload REPLACED a stored bundle with a different identity. */
  identityChanged: boolean;
  /** The superseded identity public key when identityChanged, else null. */
  previousIdentityPublicKey: string | null;
}

/**
 * Proof accompanying an upload that replaces the stored identity key
 * (registration lock, multi-device spec §6.1). Absent for the normal
 * same-identity re-upload and for a first-ever upload.
 */
export interface IdentityChangeProof {
  /** base64 XEdDSA signature by the PREVIOUS identity key. */
  signature?: string;
  /** base64 nonce this socket session was issued, echoed back. */
  nonce?: string;
}

/**
 * Thrown when an upload would replace the stored identity key without
 * authorization — neither a signature from the previous identity key nor a
 * completed reset ceremony. Nothing is written when this is thrown.
 */
export class IdentityLockedError extends Error {
  constructor() {
    super('identity_locked');
    this.name = 'IdentityLockedError';
  }
}

@Injectable()
export class KeyBundlesService {
  private readonly logger = new Logger(KeyBundlesService.name);

  constructor(
    @InjectRepository(KeyBundle)
    private readonly keyBundleRepo: Repository<KeyBundle>,
    @InjectRepository(OneTimePreKey)
    private readonly otpRepo: Repository<OneTimePreKey>,
    @InjectRepository(IdentityChangeAudit)
    private readonly identityChangeAuditRepo: Repository<IdentityChangeAudit>,
    private readonly identityResetService: IdentityResetService,
  ) {}

  /**
   * Installs the caller's public key bundle.
   *
   * Registration lock (§6.1): replacing the stored identity key requires
   * authorization, because a bundle replacement is what silently redirects
   * every future conversation to different keys. Two things authorize it:
   * a signature by the PREVIOUS identity key over the new key, the account id
   * and a session nonce, or a completed reset ceremony (§6.2) which is spent
   * here. Without either, nothing is written at all.
   *
   * Same-identity re-uploads (the client's normal every-connect path) and the
   * first-ever upload are unaffected.
   */
  async upsertKeyBundle(
    userId: number,
    data: KeyBundleData,
    proof?: IdentityChangeProof,
  ): Promise<UpsertKeyBundleResult> {
    // Detection pre-check only; races with concurrent uploads are acceptable
    // (duplicate audit rows under a race are tolerated by design — do NOT
    // serialize the upsert around this).
    const existingBundle = await this.keyBundleRepo.findOne({
      where: { userId },
    });
    const identityChanged =
      existingBundle != null &&
      existingBundle.identityPublicKey !== data.identityPublicKey;
    if (identityChanged) {
      const authorized = await this.authorizeIdentityChange(
        userId,
        existingBundle.identityPublicKey,
        data.identityPublicKey,
        proof,
      );
      if (!authorized) {
        // Loud, and deliberately before any write: an unauthorized replacement
        // attempt is exactly the event this lock exists to stop.
        this.logger.warn(
          `[identity-lock] REFUSED unauthorized identity replacement userId=${userId} storedPrefix=${existingBundle.identityPublicKey.slice(0, 12)} attemptedPrefix=${data.identityPublicKey.slice(0, 12)}`,
        );
        throw new IdentityLockedError();
      }
      this.logger.warn(
        `[identity-churn] userId=${userId} oldIdentityPrefix=${existingBundle.identityPublicKey.slice(0, 12)} newIdentityPrefix=${data.identityPublicKey.slice(0, 12)}`,
      );
    }
    // Atomic upsert — handles concurrent connections from same user (e.g. two tabs)
    await this.keyBundleRepo.upsert(
      { userId, ...data },
      { conflictPaths: ['userId'] },
    );
    // Purge unused OTPs from any SUPERSEDED identity epoch (or untagged legacy
    // rows). Belt-and-suspenders with the fetch identity filter: the filter
    // already refuses to serve them; this reclaims the slots so replenishment
    // refills the current epoch. New clients tag their OTPs with this same
    // identity, so a re-upload in either order survives (their tag matches)
    // while genuinely stale rows are removed. This is the durable fix for the
    // 2026-07-11 stale-OTP bad-MAC wave (see migrations 0003-0005).
    //
    // IDENTITY-EPOCH INVARIANT is enforced at THREE sites that MUST stay in
    // sync: (1) here — purge non-current-epoch unused rows; (2) fetchPreKeyBundle
    // — claim only current-epoch rows; (3) countUnusedPreKeys — count only
    // current-epoch rows. Change the epoch semantics in all three or none.
    await this.otpRepo
      .createQueryBuilder()
      .delete()
      .where('"userId" = :userId', { userId })
      .andWhere('used = false')
      .andWhere(
        '("identityPublicKey" IS NULL OR "identityPublicKey" != :identity)',
        { identity: data.identityPublicKey },
      )
      .execute();
    // Phase 0a takeover alarm (spec §6.0): durable audit row for the identity
    // replacement. Written AFTER the upsert so a failed upload never leaves a
    // phantom audit row. An audit-write failure must not fail the upload (that
    // would break E2E setup for the client), but it is loud — the alarm's
    // durability depends on this row.
    if (identityChanged) {
      try {
        await this.identityChangeAuditRepo.insert({
          userId,
          previousIdentityPublicKey: existingBundle.identityPublicKey,
          newIdentityPublicKey: data.identityPublicKey,
        });
      } catch (err) {
        this.logger.error(
          `[identity-churn] audit row insert FAILED userId=${userId}`,
          err instanceof Error ? err.stack : String(err),
        );
      }
    }
    this.logger.debug(`Key bundle upserted for userId=${userId}`);
    return {
      identityChanged,
      previousIdentityPublicKey: identityChanged
        ? existingBundle.identityPublicKey
        : null,
    };
  }

  /**
   * Decides whether a stored identity key may be replaced (§6.1).
   *
   * Order matters: the signature path is checked first because it is cheap and
   * self-contained, and because consuming a reset ceremony is a side effect
   * that must not happen when a perfectly good signature was supplied.
   */
  private async authorizeIdentityChange(
    userId: number,
    storedIdentityPublicKey: string,
    newIdentityPublicKey: string,
    proof?: IdentityChangeProof,
  ): Promise<boolean> {
    if (proof?.signature && proof?.nonce) {
      const signatureValid = verifyIdentityChangeSignature({
        storedIdentityPublicKey,
        newIdentityPublicKey,
        userId,
        nonce: proof.nonce,
        signature: proof.signature,
      });
      if (signatureValid) return true;
    }
    // No usable signature: only a reset ceremony that already served its full
    // delay can authorize this, and it is spent in the process (single-use).
    return this.identityResetService.consumeCompletedReset(userId);
  }

  /**
   * Read-only existence check for the caller's public key bundle. This MUST
   * not call fetchPreKeyBundle: fetching atomically consumes a one-time key.
   */
  async hasKeyBundle(userId: number): Promise<boolean> {
    return (await this.keyBundleRepo.findOne({ where: { userId } })) !== null;
  }

  /**
   * When this account's identity key was last replaced, or null if never.
   *
   * Read at connect time so a session that was offline when the replacement
   * happened still surfaces it — the durable audit row outlives the live
   * notification, which reaches only sessions connected at that moment.
   */
  async latestIdentityChangeAt(userId: number): Promise<Date | null> {
    const latest = await this.identityChangeAuditRepo.findOne({
      where: { userId },
      order: { createdAt: 'DESC' },
    });
    return latest?.createdAt ?? null;
  }

  async uploadOneTimePreKeys(
    userId: number,
    keys: OneTimePreKeyData[],
    identityPublicKey?: string,
  ): Promise<void> {
    // Untagged OTPs are cryptographic material whose identity epoch cannot be
    // proven. Never infer an epoch from the currently stored bundle: a legacy
    // client can upload an old private half after another device rotated the
    // account identity, creating a false {current identity, stale OTP} pair.
    if (!identityPublicKey) {
      this.logger.warn(
        `Rejected untagged one-time pre-keys userId=${userId} reason=identity_epoch_required`,
      );
      throw new Error('identity_epoch_required');
    }

    // UPSERT on (userId, keyId): a regenerated epoch reuses keyId slots 0..N,
    // so refresh the existing row rather than piling up duplicates.
    await this.otpRepo.upsert(
      keys.map((k) => ({
        userId,
        keyId: k.keyId,
        publicKey: k.publicKey,
        identityPublicKey,
        used: false,
      })),
      { conflictPaths: ['userId', 'keyId'] },
    );
    this.logger.debug(
      `Uploaded ${keys.length} one-time pre-keys for userId=${userId}`,
    );
  }

  async fetchPreKeyBundle(
    userId: number,
  ): Promise<PreKeyBundleResponse | null> {
    const bundle = await this.keyBundleRepo.findOne({ where: { userId } });
    if (!bundle) return null;

    // Atomic claim: UPDATE ... WHERE id = (SELECT id ... LIMIT 1) RETURNING *
    // Prevents a race where two concurrent calls serve the same OTP.
    //
    // The "identityPublicKey" = $2 filter is the DURABLE fix for the stale-OTP
    // bad-MAC wave (2026-07-11): only claim OTPs minted under the CURRENT
    // identity epoch. A row from a superseded epoch (whose private half the
    // device discarded on regeneration) or an untagged legacy row is never
    // served, so PreKey/X3DH can never build on a dead key. Safe regardless of
    // upload order — the tag, not timing, decides. See the identity-epoch
    // invariant note in upsertKeyBundle; fail-closed pinned by the unit spec.
    //
    // Postgres repo.query() returns [rows, rowCount] for UPDATE ... RETURNING
    // (see backend/CLAUDE.md §4) — destructuring the row directly reads the
    // rows ARRAY and silently serves oneTimePreKey* as null while still
    // burning the OTP (used=true). Caught by the test_e2e wire harness.
    const [rows] = (await this.otpRepo.query(
      `UPDATE one_time_pre_keys
         SET used = true
       WHERE id = (
         SELECT id FROM one_time_pre_keys
         WHERE "userId" = $1 AND used = false AND "identityPublicKey" = $2
         ORDER BY id ASC
         LIMIT 1
       )
       RETURNING id, "keyId", "publicKey"`,
      [userId, bundle.identityPublicKey],
    )) as [Array<{ id: number; keyId: number; publicKey: string }>, number];
    const otp = rows[0];

    if (!otp) {
      this.logger.warn(
        `OTP exhausted for userId=${userId}: serving bundle without one-time pre-key`,
      );
    }

    return {
      registrationId: bundle.registrationId,
      identityPublicKey: bundle.identityPublicKey,
      signedPreKeyId: bundle.signedPreKeyId,
      signedPreKeyPublic: bundle.signedPreKeyPublic,
      signedPreKeySignature: bundle.signedPreKeySignature,
      oneTimePreKeyId: otp?.keyId ?? null,
      oneTimePreKeyPublic: otp?.publicKey ?? null,
    };
  }

  async countUnusedPreKeys(userId: number): Promise<number> {
    // Count only the CURRENT epoch — stale rows from a superseded identity are
    // never served, so they must not inflate the count and suppress the
    // preKeysLow replenishment signal.
    const bundle = await this.keyBundleRepo.findOne({ where: { userId } });
    if (!bundle) return 0;
    return this.otpRepo.count({
      where: {
        userId,
        used: false,
        identityPublicKey: bundle.identityPublicKey,
      },
    });
  }

  async deleteByUserId(userId: number): Promise<void> {
    await this.otpRepo.delete({ userId });
    await this.keyBundleRepo.delete({ userId });
    this.logger.log(`Deleted all key data for userId=${userId}`);
  }
}
