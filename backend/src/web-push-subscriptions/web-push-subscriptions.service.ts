import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { WebPushSubscription } from './web-push-subscription.entity';

interface WebPushSubscriptionUpsertInput {
  userId: number;
  endpoint: string;
  p256dh: string;
  auth: string;
  userAgent?: string | null;
  expirationTime?: number | null;
}

@Injectable()
export class WebPushSubscriptionsService {
  constructor(
    @InjectRepository(WebPushSubscription)
    private readonly subscriptionRepo: Repository<WebPushSubscription>,
  ) {}

  async upsert(input: WebPushSubscriptionUpsertInput): Promise<void> {
    await this.subscriptionRepo.upsert(
      {
        userId: input.userId,
        endpoint: input.endpoint,
        p256dh: input.p256dh,
        auth: input.auth,
        userAgent: input.userAgent ?? null,
        expirationTime:
          input.expirationTime == null ? null : String(input.expirationTime),
      },
      ['endpoint'],
    );
  }

  async removeByEndpointForUser(userId: number, endpoint: string): Promise<void> {
    await this.subscriptionRepo.delete({ userId, endpoint });
  }

  async removeByUserId(userId: number): Promise<void> {
    await this.subscriptionRepo.delete({ userId });
  }

  async removeByEndpoints(endpoints: string[]): Promise<void> {
    if (!endpoints.length) return;
    await this.subscriptionRepo
      .createQueryBuilder()
      .delete()
      .from(WebPushSubscription)
      .where('endpoint IN (:...endpoints)', { endpoints })
      .execute();
  }

  async findByUserId(userId: number): Promise<WebPushSubscription[]> {
    return this.subscriptionRepo.find({ where: { userId } });
  }
}
