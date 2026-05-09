import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { PassportModule } from '@nestjs/passport';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { JwtStrategy } from './strategies/jwt.strategy';
import { UsersModule } from '../users/users.module';

const DEV_JWT_SECRET = 'super-secret-dev-key';

@Module({
  imports: [
    UsersModule,
    PassportModule,
    ConfigModule,
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => {
        const secret = configService.get<string>('JWT_SECRET') || DEV_JWT_SECRET;
        const isProd = configService.get('NODE_ENV') === 'production';
        if (isProd && (!secret || secret === DEV_JWT_SECRET)) {
          throw new Error(
            'Production requires a strong JWT_SECRET. Do not use the dev fallback.',
          );
        }
        return {
          secret,
          // Phase 0 hotfix (2026-05-09): bumped from 24h to 30d so PWA users
          // are not auto-logged-out daily while Phase 1 (identity-key auth,
          // see docs/superpowers/specs/2026-05-09-identity-key-auth-design.md)
          // is being built. Will be replaced by short-lived (~2h) session
          // tokens + Ed25519 silent refresh in Phase 1.
          signOptions: { expiresIn: '30d' },
        };
      },
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy],
  exports: [AuthService, JwtModule],
})
export class AuthModule {}
