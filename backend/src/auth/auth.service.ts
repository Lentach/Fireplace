import { Injectable, UnauthorizedException, Logger } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { User } from '../users/user.entity';
import { UsersService } from '../users/users.service';
import { RefreshTokensService } from './refresh-tokens.service';
import { DEFAULT_DEVICE_ID } from '../key-bundles/key-bundles.service';

// Precomputed bcrypt hash used for a constant-time comparison when the
// identifier matches no user, so "no such user" takes the same time as a wrong
// password (defeats timing-based user enumeration). The value is arbitrary.
const TIMING_SAFE_DUMMY_HASH =
  '$2b$10$pwiFDkB3zcAu0PKQqI13b.fGqVMlVlB8aCB22BL/qyvTghAEiP2N2';

@Injectable()
export class AuthService {
  private readonly auditLogger = new Logger('Audit');

  constructor(
    private usersService: UsersService,
    private jwtService: JwtService,
    private refreshTokensService: RefreshTokensService,
  ) {}

  async register(username: string, password: string) {
    // Password strength is validated at the DTO layer (RegisterDto)
    const user = await this.usersService.create(username, password);
    return { id: user.id, username: user.username, tag: user.tag };
  }

  async login(identifier: string, password: string) {
    let user: User | null = null;
    if (identifier.includes('#')) {
      const [u, t] = identifier.split('#');
      if (u && t)
        user = await this.usersService.findByUsernameAndTag(u.trim(), t.trim());
    } else {
      const users = await this.usersService.findByUsername(identifier.trim());
      if (users.length === 1) user = users[0];
      else if (users.length > 1) {
        // Ambiguous bare username: do NOT reveal that several accounts share
        // this name (user enumeration) and do NOT short-circuit before the
        // bcrypt compare below. Leaving `user` null routes this through the
        // constant-time dummy-compare path, so an ambiguous username is
        // indistinguishable — textually and by timing — from any other bad
        // login. Username lookup stays case-insensitive (findByUsername).
        this.auditLogger.log(
          `login failed identifier=${identifier} (multiple users)`,
        );
      }
    }
    if (!user) {
      // Constant-time guard: perform a real bcrypt compare so a missing user
      // is indistinguishable by timing from a wrong password.
      await bcrypt.compare(password, TIMING_SAFE_DUMMY_HASH);
      this.auditLogger.log(`login failed identifier=${identifier}`);
      throw new UnauthorizedException('Invalid credentials');
    }

    const passwordValid = await bcrypt.compare(password, user.password);
    if (!passwordValid) {
      this.auditLogger.log(`login failed identifier=${identifier}`);
      throw new UnauthorizedException('Invalid credentials');
    }

    this.auditLogger.log(
      `login success userId=${user.id} username=${user.username}`,
    );

    // Every session belongs to a device (Phase 1, spec §4). Until provisioning
    // ships (Phase 2) an account has exactly one device, so every login is
    // device 1 — the claim exists now so the socket, key material and push
    // targeting can all key on it without another token migration later.
    const deviceId = DEFAULT_DEVICE_ID;
    const payload = {
      sub: user.id,
      username: user.username,
      tag: user.tag,
      deviceId,
    };
    const refresh_token = await this.refreshTokensService.createToken(
      user.id,
      deviceId,
    );
    return {
      access_token: this.jwtService.sign(payload),
      refresh_token,
    };
  }

  async refreshWithToken(refreshTokenPlain: string) {
    const session =
      await this.refreshTokensService.consumeAndSlide(refreshTokenPlain);
    const user = await this.usersService.findById(session.userId);
    if (!user) {
      throw new UnauthorizedException();
    }
    const payload = {
      sub: user.id,
      username: user.username,
      tag: user.tag,
      // The refresh row remembers which device the session belongs to; a row
      // predating the column is device 1 (§8).
      deviceId: session.deviceId ?? DEFAULT_DEVICE_ID,
    };
    return {
      access_token: this.jwtService.sign(payload),
      refresh_token: refreshTokenPlain,
    };
  }

  async logoutRefreshToken(refreshTokenPlain: string): Promise<void> {
    await this.refreshTokensService.revokeByPlain(refreshTokenPlain);
  }
}
