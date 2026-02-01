import { Injectable, UnauthorizedException, BadRequestException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { UsersService } from '../users/users.service';

@Injectable()
export class AuthService {
  // Password strength requirements
  private PASSWORD_MIN_LENGTH = 8;
  private PASSWORD_REGEX = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[a-zA-Z\d\s@$!%*?&]{8,}$/;

  constructor(
    private usersService: UsersService,
    private jwtService: JwtService,
  ) {}

  private validatePassword(password: string): void {
    if (password.length < this.PASSWORD_MIN_LENGTH) {
      throw new BadRequestException(
        `Password must be at least ${this.PASSWORD_MIN_LENGTH} characters long`,
      );
    }

    if (!this.PASSWORD_REGEX.test(password)) {
      throw new BadRequestException(
        'Password must contain at least one uppercase letter, one lowercase letter, and one number',
      );
    }
  }

  async register(email: string, password: string, username?: string) {
    this.validatePassword(password);
    const user = await this.usersService.create(email, password, username);
    // Don't return the password in the response
    return { id: user.id, email: user.email, username: user.username };
  }

  async login(email: string, password: string) {
    const user = await this.usersService.findByEmail(email);
    if (!user) {
      throw new UnauthorizedException('Invalid credentials');
    }

    const passwordValid = await bcrypt.compare(password, user.password);
    if (!passwordValid) {
      throw new UnauthorizedException('Invalid credentials');
    }

    // Token payload — sub is the JWT standard for "subject" (user id)
    const payload = {
      sub: user.id,
      email: user.email,
      username: user.username,
      profilePictureUrl: user.profilePictureUrl,
      activeStatus: user.activeStatus,
    };
    return {
      access_token: this.jwtService.sign(payload),
    };
  }
}
