import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { KeyBundle } from './key-bundle.entity';
import { OneTimePreKey } from './one-time-pre-key.entity';

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

@Injectable()
export class KeyBundlesService {
  private readonly logger = new Logger(KeyBundlesService.name);

  constructor(
    @InjectRepository(KeyBundle)
    private readonly keyBundleRepo: Repository<KeyBundle>,
    @InjectRepository(OneTimePreKey)
    private readonly otpRepo: Repository<OneTimePreKey>,
  ) {}

  async upsertKeyBundle(userId: number, data: KeyBundleData): Promise<void> {
    // Telemetry pre-check only; races with concurrent uploads are acceptable.
    const existingBundle = await this.keyBundleRepo.findOne({
      where: { userId },
    });
    if (
      existingBundle &&
      existingBundle.identityPublicKey !== data.identityPublicKey
    ) {
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
    this.logger.debug(`Key bundle upserted for userId=${userId}`);
  }

  /**
   * Read-only existence check for the caller's public key bundle. This MUST
   * not call fetchPreKeyBundle: fetching atomically consumes a one-time key.
   */
  async hasKeyBundle(userId: number): Promise<boolean> {
    return (await this.keyBundleRepo.findOne({ where: { userId } })) !== null;
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
