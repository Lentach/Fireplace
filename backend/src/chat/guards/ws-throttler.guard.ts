import { ExecutionContext, Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
import { Socket } from 'socket.io';

@Injectable()
export class WsThrottlerGuard extends ThrottlerGuard {
  protected getRequestResponse(context: ExecutionContext) {
    const client = context.switchToWs().getClient<Socket>();
    // ThrottlerGuard expects res.header() for rate-limit headers; Socket has no such method.
    // Provide mock res with no-op header() (returns this for chaining).
    const mockRes = {
      header: function (_name: string, _value?: string | number) {
        return this;
      },
    } as unknown as Record<string, unknown>;
    const req = {
      headers: client.handshake?.headers ?? {},
      ...client,
    } as unknown as Record<string, unknown>;
    return { req, res: mockRes };
  }

  protected async getTracker(req: Record<string, unknown>): Promise<string> {
    const socket = req as unknown as Socket;
    return (
      (socket.data?.user as { id?: number } | undefined)?.id?.toString() ??
      socket.handshake?.address ??
      'unknown'
    );
  }
}
