import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { createHash, randomBytes } from 'crypto';
import { RefreshToken } from './refresh-token.entity';

const REFRESH_TOKEN_BYTE_LENGTH = 48;
/** Opaque refresh tokens remain valid for this long (sliding on each refresh). */
export const REFRESH_TOKEN_TTL_DAYS = 365;

@Injectable()
export class RefreshTokensService {
  private readonly logger = new Logger(RefreshTokensService.name);

  constructor(
    @InjectRepository(RefreshToken)
    private readonly refreshRepo: Repository<RefreshToken>,
  ) {}

  static hashToken(plain: string): string {
    return createHash('sha256').update(plain, 'utf8').digest('hex');
  }

  private expiresAtFromNow(): Date {
    const expiresAt = new Date();
    expiresAt.setUTCDate(expiresAt.getUTCDate() + REFRESH_TOKEN_TTL_DAYS);
    return expiresAt;
  }

  /**
   * Persists a new refresh session and returns the plaintext token (client-only).
   */
  async createToken(userId: number): Promise<string> {
    const plain = randomBytes(REFRESH_TOKEN_BYTE_LENGTH).toString('base64url');
    const tokenHash = RefreshTokensService.hashToken(plain);
    const expiresAt = this.expiresAtFromNow();

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
   * Validates a plaintext refresh token and extends its expiry.
   *
   * This deliberately keeps the opaque refresh token stable. Hard single-use
   * rotation turns a lost `/auth/refresh` response into a self-inflicted logout:
   * the server has already deleted the row, while the client can only retry the
   * old token. Sliding the existing row preserves sticky sessions without
   * weakening explicit revoke/password-change invalidation.
   */
  async consumeAndSlide(plain: string): Promise<number> {
    const tokenHash = RefreshTokensService.hashToken(plain);
    const row = await this.refreshRepo.findOne({ where: { tokenHash } });
    if (!row) {
      this.logger.warn(
        '[auth-session-end] reason=refresh_invalid source=refresh_endpoint hasUser=false',
      );
      throw new UnauthorizedException('Invalid refresh token');
    }
    if (new Date(row.expiresAt).getTime() <= Date.now()) {
      this.logger.warn(
        `[auth-session-end] reason=refresh_expired source=refresh_endpoint userId=${row.userId}`,
      );
      await this.refreshRepo.remove(row);
      throw new UnauthorizedException('Refresh token expired');
    }

    row.expiresAt = this.expiresAtFromNow();
    await this.refreshRepo.save(row);
    return row.userId;
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
