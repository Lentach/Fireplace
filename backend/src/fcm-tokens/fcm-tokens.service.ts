import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { FcmToken } from './fcm-token.entity';

@Injectable()
export class FcmTokensService {
  private readonly logger = new Logger(FcmTokensService.name);

  constructor(
    @InjectRepository(FcmToken)
    private readonly fcmTokenRepo: Repository<FcmToken>,
  ) {}

  async upsert(userId: number, token: string, platform: string): Promise<void> {
    await this.fcmTokenRepo.upsert({ userId, token, platform }, ['token']);
  }

  async removeByToken(token: string): Promise<void> {
    await this.fcmTokenRepo.delete({ token });
  }

  async removeByTokenForUser(userId: number, token: string): Promise<void> {
    await this.fcmTokenRepo.delete({ userId, token });
  }

  async removeByUserId(userId: number): Promise<void> {
    await this.fcmTokenRepo.delete({ userId });
  }

  async findTokensByUserId(
    userId: number,
    platforms?: string[],
  ): Promise<string[]> {
    const rows = await this.fcmTokenRepo.find({ where: { userId } });
    if (!platforms?.length) {
      return rows.map((r) => r.token);
    }
    const allowed = new Set(platforms);
    return rows.filter((r) => allowed.has(r.platform)).map((r) => r.token);
  }

  async findRowsByUserId(userId: number): Promise<FcmToken[]> {
    return this.fcmTokenRepo.find({ where: { userId } });
  }

  async findRowsByUserIdAndPlatforms(
    userId: number,
    platforms: string[],
  ): Promise<FcmToken[]> {
    const rows = await this.fcmTokenRepo.find({ where: { userId } });
    const allowed = new Set(platforms);
    return rows.filter((r) => allowed.has(r.platform));
  }

  async removeByTokens(tokens: string[]): Promise<void> {
    if (!tokens.length) return;
    await this.fcmTokenRepo
      .createQueryBuilder()
      .delete()
      .from(FcmToken)
      .where('token IN (:...tokens)', { tokens })
      .execute();
  }

}
