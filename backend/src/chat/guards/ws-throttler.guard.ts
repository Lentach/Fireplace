import { ExecutionContext, Injectable } from '@nestjs/common';
import { ThrottlerGuard, ThrottlerException } from '@nestjs/throttler';

@Injectable()
export class WsThrottlerGuard extends ThrottlerGuard {
  async canActivate(context: ExecutionContext): Promise<boolean> {
    const client = context.switchToWs().getClient();
    const userId: string =
      client.data?.user?.id?.toString() ??
      client.handshake?.address ??
      'unknown';

    // Use userId as the throttler tracking key
    const { ttl, limit } = this.options[0];
    const key = `ws_throttle_${userId}`;

    const { totalHits } = await this.storageService.increment(
      key,
      ttl,
      limit,
      ttl,
      'default',
    );

    if (totalHits > limit) {
      throw new ThrottlerException();
    }
    return true;
  }
}
