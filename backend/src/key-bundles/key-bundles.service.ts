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
    this.logger.log(`Key bundle upserted for userId=${userId}`);
  }

  async uploadOneTimePreKeys(
    userId: number,
    keys: OneTimePreKeyData[],
  ): Promise<void> {
    const entities = keys.map((k) =>
      this.otpRepo.create({ userId, keyId: k.keyId, publicKey: k.publicKey }),
    );
    await this.otpRepo.save(entities);
    this.logger.log(
      `Uploaded ${keys.length} one-time pre-keys for userId=${userId}`,
    );
  }

  async fetchPreKeyBundle(
    userId: number,
  ): Promise<PreKeyBundleResponse | null> {
    const bundle = await this.keyBundleRepo.findOne({ where: { userId } });
    if (!bundle) return null;

    // Find one unused OTP and mark it as used
    const otp = await this.otpRepo.findOne({
      where: { userId, used: false },
      order: { id: 'ASC' },
    });

    if (otp) {
      otp.used = true;
      await this.otpRepo.save(otp);
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
