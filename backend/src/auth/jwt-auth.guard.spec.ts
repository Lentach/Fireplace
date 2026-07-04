import {
  ExecutionContext,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtAuthGuard } from './jwt-auth.guard';

describe('JwtAuthGuard', () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('logs invalid access reason without leaking URL query strings', () => {
    const warnSpy = jest
      .spyOn(Logger.prototype, 'warn')
      .mockImplementation(() => undefined);
    const guard = new JwtAuthGuard();
    const info = new Error('jwt malformed');
    info.name = 'JsonWebTokenError';
    const context = {
      switchToHttp: () => ({
        getRequest: () => ({
          method: 'GET',
          url: '/users/search?q=alice&token=do-not-log',
        }),
      }),
    } as unknown as ExecutionContext;

    expect(() => guard.handleRequest(null, null, info, context)).toThrow(
      UnauthorizedException,
    );

    expect(warnSpy).toHaveBeenCalledTimes(1);
    const logLine = warnSpy.mock.calls[0][0] as string;
    expect(logLine).toContain('reason=invalid_signature');
    expect(logLine).toContain('path=/users/search');
    expect(logLine).not.toContain('q=alice');
    expect(logLine).not.toContain('do-not-log');
  });
});
