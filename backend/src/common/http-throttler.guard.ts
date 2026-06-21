import { ExecutionContext, Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';

/**
 * HTTP-only rate-limit guard, registered globally via APP_GUARD.
 *
 * Why a custom guard:
 * - The backend runs behind nginx, which sets `X-Real-IP = $remote_addr`. The default
 *   ThrottlerGuard tracker uses `req.ip`, which (without trust-proxy) resolves to the
 *   nginx upstream — so EVERY client would share one bucket (a global lockout). We track
 *   the real client IP from `X-Real-IP` (then `X-Forwarded-For`, then `req.ip`).
 * - As a global guard it would otherwise also run on the WebSocket gateway and crash on
 *   `res.header()` (sockets have no HTTP response). We skip non-HTTP contexts; WS keeps
 *   its own `WsThrottlerGuard`.
 */
@Injectable()
export class HttpThrottlerGuard extends ThrottlerGuard {
  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (context.getType() !== 'http') return true;
    return super.canActivate(context);
  }

  protected getTracker(req: Record<string, unknown>): Promise<string> {
    // Express request headers; nginx controls X-Real-IP, so it is not client-spoofable.
    const headers = (req.headers ?? {}) as Record<
      string,
      string | string[] | undefined
    >;
    const firstHop = (value: string | string[] | undefined): string | undefined => {
      if (Array.isArray(value)) return value[0]?.trim();
      if (typeof value === 'string') return value.split(',')[0]?.trim();
      return undefined;
    };
    const tracker =
      firstHop(headers['x-real-ip']) ??
      firstHop(headers['x-forwarded-for']) ??
      (typeof req.ip === 'string' ? req.ip : undefined) ??
      'unknown';
    return Promise.resolve(tracker);
  }
}
