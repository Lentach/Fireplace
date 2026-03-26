import { ExecutionContext } from '@nestjs/common';
import { WsThrottlerGuard } from './ws-throttler.guard';

describe('WsThrottlerGuard', () => {
  let guard: WsThrottlerGuard;

  beforeEach(() => {
    // WsThrottlerGuard extends ThrottlerGuard; we only test the two overridden methods
    guard = new WsThrottlerGuard({} as any, {} as any, {} as any);
  });

  describe('getRequestResponse', () => {
    it('returns req derived from socket handshake headers', () => {
      const mockSocket = {
        handshake: { headers: { 'x-forwarded-for': '1.2.3.4' }, address: '127.0.0.1' },
        data: { user: { id: 42 } },
      };
      const context = {
        switchToWs: () => ({ getClient: () => mockSocket }),
      } as unknown as ExecutionContext;

      const { req, res } = (guard as any).getRequestResponse(context);

      // req must expose headers
      expect(req.headers).toEqual(mockSocket.handshake.headers);
      // res.header must be callable without throwing (no-op mock)
      expect(() => res.header('X-RateLimit-Limit', '100')).not.toThrow();
    });

    it('res.header() returns the res object for chaining', () => {
      const mockSocket = {
        handshake: { headers: {}, address: '127.0.0.1' },
        data: { user: { id: 1 } },
      };
      const context = {
        switchToWs: () => ({ getClient: () => mockSocket }),
      } as unknown as ExecutionContext;

      const { res } = (guard as any).getRequestResponse(context);
      const result = res.header('X-Test', 'value');
      expect(result).toBe(res);
    });
  });

  describe('getTracker', () => {
    it('returns user id string when socket.data.user is set', async () => {
      const req = { data: { user: { id: 99 } }, handshake: { address: '1.2.3.4' } };
      const tracker = await (guard as any).getTracker(req);
      expect(tracker).toBe('99');
    });

    it('falls back to handshake address when no user', async () => {
      const req = { data: {}, handshake: { address: '5.6.7.8' } };
      const tracker = await (guard as any).getTracker(req);
      expect(tracker).toBe('5.6.7.8');
    });

    it('falls back to "unknown" when neither user nor address', async () => {
      const req = { data: {}, handshake: {} };
      const tracker = await (guard as any).getTracker(req);
      expect(tracker).toBe('unknown');
    });
  });
});
