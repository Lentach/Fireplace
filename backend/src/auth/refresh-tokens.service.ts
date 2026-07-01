import { Injectable, UnauthorizedException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { createHash, randomBytes } from 'crypto';
import { RefreshToken } from './refresh-token.entity';

const REFRESH_TOKEN_BYTE_LENGTH = 48;
/** Opaque refresh tokens remain valid for this long (sliding on each refresh). */
export const REFRESH_TOKEN_TTL_DAYS = 365;

@Injectable()
export class RefreshTokensService {
  constructor(
    @InjectRepository(RefreshToken)
    private readonly refreshRepo: Repository<RefreshToken>,
  ) {}

  static hashToken(plain: string): string {
    return createHash('sha256').update(plain, 'utf8').digest('hex');
  }

  /**
   * Persists a new refresh session and returns the plaintext token (client-only).
   */
  async createToken(userId: number): Promise<string> {
    const plain = randomBytes(REFRESH_TOKEN_BYTE_LENGTH).toString('base64url');
    const tokenHash = RefreshTokensService.hashToken(plain);
    const expiresAt = new Date();
    expiresAt.setUTCDate(expiresAt.getUTCDate() + REFRESH_TOKEN_TTL_DAYS);

    await this.refreshRepo.save(
      this.refreshRepo.create({
        userId,
        tokenHash,
        expiresAt,
      }),
    );
    return plain;
  }

  /**
   * Validates plaintext refresh token, rotates it (old row deleted), returns user id.
   * Caller issues new JWT + createToken for the pair returned... actually rotation:
   * we delete old hash and issue new plain in same transaction pattern via createToken after validate.
   */
  async consumeAndRotate(plain: string): Promise<{ userId: number; newPlain: string }> {
    const tokenHash = RefreshTokensService.hashToken(plain);
    const row = await this.refreshRepo.findOne({ where: { tokenHash } });
    if (!row) {
      throw new UnauthorizedException('Invalid refresh token');
    }
    if (new Date(row.expiresAt).getTime() <= Date.now()) {
      await this.refreshRepo.remove(row);
      throw new UnauthorizedException('Refresh token expired');
    }

    const userId = row.userId;
    await this.refreshRepo.remove(row);

    const newPlain = await this.createToken(userId);
    return { userId, newPlain };
  }

  async revokeByPlain(plain: string): Promise<void> {
    const tokenHash = RefreshTokensService.hashToken(plain);
    const row = await this.refreshRepo.findOne({ where: { tokenHash } });
    if (row) {
      await this.refreshRepo.remove(row);
    }
  }

  async revokeAllForUser(userId: number): Promise<void> {
    await this.refreshRepo.delete({ userId });
  }

}
