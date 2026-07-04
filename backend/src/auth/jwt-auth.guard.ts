import {
  ExecutionContext,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

// Guard for protecting endpoints — add @UseGuards(JwtAuthGuard)
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  private readonly logger = new Logger(JwtAuthGuard.name);

  private requestPath(req: {
    route?: { path?: string };
    url?: string;
  }): string {
    if (req.route?.path) return req.route.path;
    return (req.url ?? 'unknown').split('?')[0] || 'unknown';
  }

  handleRequest<TUser = any>(
    err: Error | null,
    user: TUser,
    info: Error | null,
    context: ExecutionContext,
  ): TUser {
    if (err || !user) {
      const req = context.switchToHttp().getRequest<{
        method?: string;
        route?: { path?: string };
        url?: string;
        ip?: string;
      }>();
      const reason =
        info?.name === 'TokenExpiredError'
          ? 'access_expired'
          : info?.name === 'JsonWebTokenError'
            ? 'invalid_signature'
            : 'access_invalid';
      const path = this.requestPath(req);
      this.logger.warn(
        `[auth-session-end] reason=${reason} source=http_guard method=${req.method ?? 'unknown'} path=${path} errorType=${info?.name ?? err?.name ?? 'none'}`,
      );
      throw err || new UnauthorizedException();
    }
    return user;
  }
}
