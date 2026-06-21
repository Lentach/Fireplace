import { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ThrottlerStorage, ThrottlerModuleOptions } from '@nestjs/throttler';
import { HttpThrottlerGuard } from './http-throttler.guard';

// The two overridden methods don't touch storage/options; supply typed stubs.
const makeGuard = () =>
  new HttpThrottlerGuard(
    { throttlers: [] } as unknown as ThrottlerModuleOptions,
    {} as unknown as ThrottlerStorage,
    new Reflector(),
  );

// Expose the protected getTracker without `any`.
type TrackerGuard = { getTracker(req: Record<string, unknown>): Promise<string> };

describe('HttpThrottlerGuard', () => {
  it('skips non-HTTP contexts so it never runs on the WS gateway', async () => {
    const guard = makeGuard();
    const wsCtx = { getType: () => 'ws' } as unknown as ExecutionContext;
    await expect(guard.canActivate(wsCtx)).resolves.toBe(true);
  });

  it('tracks the real client via X-Real-IP, not the nginx upstream', async () => {
    const guard = makeGuard() as unknown as TrackerGuard;
    const tracker = await guard.getTracker({
      headers: { 'x-real-ip': '203.0.113.7' },
      ip: '127.0.0.1',
    });
    expect(tracker).toBe('203.0.113.7');
  });

  it('falls back to X-Forwarded-For first hop, then req.ip', async () => {
    const guard = makeGuard() as unknown as TrackerGuard;
    expect(
      await guard.getTracker({ headers: { 'x-forwarded-for': '198.51.100.9, 10.0.0.1' } }),
    ).toBe('198.51.100.9');
    expect(await guard.getTracker({ headers: {}, ip: '192.0.2.5' })).toBe('192.0.2.5');
  });
});
