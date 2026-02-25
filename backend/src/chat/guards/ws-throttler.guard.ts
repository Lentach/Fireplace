import { ExecutionContext, Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
import { Socket } from 'socket.io';

@Injectable()
export class WsThrottlerGuard extends ThrottlerGuard {
  protected getRequestResponse(context: ExecutionContext) {
    const client = context.switchToWs().getClient<Socket>();
    // For WebSocket, both req and res point to the client socket
    return { req: client as unknown as Record<string, unknown>, res: client as unknown as Record<string, unknown> };
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
