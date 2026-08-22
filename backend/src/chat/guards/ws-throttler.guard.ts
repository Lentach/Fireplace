import { ExecutionContext, Injectable, Logger } from '@nestjs/common';
import { ThrottlerGuard, ThrottlerLimitDetail } from '@nestjs/throttler';
import { MESSAGE_METADATA } from '@nestjs/websockets/constants';
import { Socket } from 'socket.io';

/** The stable refusal code every throttled handler answers with. */
export const RATE_LIMITED = 'rate_limited';

/**
 * How each throttled request ANSWERS when it is rate limited: the response
 * event of that request, plus the refusal body in that event's own shape.
 *
 * This table exists because the alternative is silence. `ThrottlerGuard` throws
 * `ThrottlerException`, Nest turns an unhandled WS exception into an
 * `exception` event, and this app's client listens to ~60 NAMED events plus
 * `error` — never `exception`. So before this table a throttled request was
 * answered by nothing at all, and any client state staked on the answer was
 * stranded: a throttled `editMessage` left an optimistically applied edit on
 * that device FOREVER while the server and the peer kept the old text, which is
 * the same divergence the `deviceListStale` edit path was fixed for.
 *
 * Answering in each request's OWN contract, rather than through one new global
 * "rate limited" event, is deliberate. Every refusal in this codebase is an
 * answer on the request's own response event with a stable code, so a second
 * refusal convention would be one more thing every future handler must
 * remember — and the client would need a map from that event to whichever
 * optimistic state to unwind. In-contract needs no such map: these payloads
 * flow into the settle/revert paths the client ALREADY has.
 *
 * A handler that is not listed falls back to `error { message }`, which the
 * client already listens to and which already marks in-flight sends failed. So
 * an unlisted handler degrades to a visible error, never to silence.
 */
const THROTTLE_ANSWERS: Record<
  string,
  (data: unknown, retryAfterMs: number) => [string, Record<string, unknown>]
> = {
  // Reverts the optimistic edit through the existing `onEditMessageFailed`.
  editMessage: (data, retryAfterMs) => [
    'editMessageFailed',
    {
      messageId: (data as { messageId?: number } | null)?.messageId,
      reason: RATE_LIMITED,
      retryAfterMs,
    },
  ],
  // The link ceremony: each stage answers its own ack, so a throttled stage
  // surfaces in the link UI instead of hanging it.
  openProvisioning: (_data, retryAfterMs) => [
    'provisioningOpened',
    { success: false, error: RATE_LIMITED, retryAfterMs },
  ],
  provisioningHello: (_data, retryAfterMs) => [
    'provisioningHelloAck',
    { success: false, error: RATE_LIMITED, retryAfterMs },
  ],
  provisionDevice: (_data, retryAfterMs) => [
    'provisionDeviceAck',
    { success: false, error: RATE_LIMITED, retryAfterMs },
  ],
  provisioningComplete: (_data, retryAfterMs) => [
    'provisioningCompleted',
    { success: false, error: RATE_LIMITED, retryAfterMs },
  ],
  cancelProvisioning: (_data, retryAfterMs) => [
    'provisioningCancelled',
    { success: false, error: RATE_LIMITED, retryAfterMs },
  ],
  revokeDevice: (_data, retryAfterMs) => [
    'deviceRevocationCompleted',
    { success: false, error: RATE_LIMITED, retryAfterMs },
  ],
  updateDeviceList: (_data, retryAfterMs) => [
    'deviceListUpdated',
    { success: false, error: RATE_LIMITED, retryAfterMs },
  ],
  uploadKeyBundle: (_data, retryAfterMs) => [
    'keyBundleUploaded',
    { success: false, error: RATE_LIMITED, retryAfterMs },
  ],
};

@Injectable()
export class WsThrottlerGuard extends ThrottlerGuard {
  private readonly wsLogger = new Logger(WsThrottlerGuard.name);

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

  /**
   * ANSWER the caller, then refuse.
   *
   * The throw still happens, so the handler never runs and the limit keeps its
   * teeth; the emit only ensures the caller learns why. Emitting before the
   * throw (rather than from an exception filter) keeps the decision next to the
   * table that defines it.
   */
  protected async throwThrottlingException(
    context: ExecutionContext,
    detail: ThrottlerLimitDetail,
  ): Promise<void> {
    try {
      const client = context.switchToWs().getClient<Socket>();
      const event = Reflect.getMetadata(
        MESSAGE_METADATA,
        context.getHandler(),
      ) as string | undefined;
      // `timeToExpire` is seconds until the window rolls; the client needs it to
      // say "try again in N minutes" instead of guessing.
      const retryAfterMs = Math.max(0, (detail.timeToExpire ?? 0) * 1000);
      const answer = event ? THROTTLE_ANSWERS[event] : undefined;
      const [name, payload] = answer
        ? answer(context.switchToWs().getData(), retryAfterMs)
        : ['error', { message: RATE_LIMITED, event, retryAfterMs }];
      const userId = (client.data?.user as { id?: number } | undefined)?.id;
      this.wsLogger.warn(
        `[throttle] REFUSED event=${event ?? 'unknown'} userId=${userId ?? 'anon'} answeredWith=${name} retryAfterMs=${retryAfterMs}`,
      );
      client.emit(name, payload);
    } catch (error) {
      // Never let the courtesy answer mask the refusal itself.
      this.wsLogger.error(
        `[throttle] could not answer the caller: ${(error as Error).message}`,
      );
    }
    return super.throwThrottlingException(context, detail);
  }
}
