import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { UsersService } from '../../users/users.service';

// Passport strategy — automatically verifies the JWT token
// and injects user data into request.user
@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(private usersService: UsersService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      secretOrKey: process.env.JWT_SECRET || 'super-secret-dev-key',
    });
  }

  // Passport calls this method after verifying the token signature.
  // Returns the user object which will be available in request.user.
  async validate(payload: {
    sub: number;
    email: string;
    username: string;
    profilePictureUrl: string;
  }) {
    const user = await this.usersService.findById(payload.sub);
    if (!user) {
      throw new UnauthorizedException();
    }
    return {
      id: user.id,
      email: user.email,
      username: user.username,
      profilePictureUrl: user.profilePictureUrl,
    };
  }
}
