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
    // Atomic upsert — handles concurrent connections from same user (e.g. two tabs)
    await this.keyBundleRepo.upsert(
      { userId, ...data },
      { conflictPaths: ['userId'] },
    );
    this.logger.debug(`Key bundle upserted for userId=${userId}`);
  }

  async uploadOneTimePreKeys(
    userId: number,
    keys: OneTimePreKeyData[],
  ): Promise<void> {
    const entities = keys.map((k) =>
      this.otpRepo.create({ userId, keyId: k.keyId, publicKey: k.publicKey }),
    );
    await this.otpRepo.save(entities);
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
    // Prevents race condition where two concurrent calls serve the same OTP.
    const [otp]: Array<{ id: number; keyId: number; publicKey: string } | undefined> =
      await this.otpRepo.query(
        `UPDATE one_time_pre_keys
           SET used = true
         WHERE id = (
           SELECT id FROM one_time_pre_keys
           WHERE "userId" = $1 AND used = false
           ORDER BY id ASC
           LIMIT 1
         )
         RETURNING id, "keyId", "publicKey"`,
        [userId],
      );

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
    return this.otpRepo.count({ where: { userId, used: false } });
  }

  async deleteByUserId(userId: number): Promise<void> {
    await this.otpRepo.delete({ userId });
    await this.keyBundleRepo.delete({ userId });
    this.logger.log(`Deleted all key data for userId=${userId}`);
  }
}
