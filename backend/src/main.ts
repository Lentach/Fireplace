import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  const logger = new Logger('Bootstrap');
  const configService = app.get(ConfigService);

  // Security headers (X-Content-Type-Options, X-Frame-Options, etc.)
  app.use(helmet());

  // ValidationPipe validates DTOs (e.g. checks if email is valid).
  // whitelist: true — strips properties not defined in the DTO (security).
  app.useGlobalPipes(new ValidationPipe({ whitelist: true }));

  // Allow cross-origin requests from the Flutter frontend
  // Use ConfigService for environment-based CORS instead of hardcoded origin
  const allowedOrigins = (
    configService.get('ALLOWED_ORIGINS') || 'http://localhost:3000'
  )
    .split(',')
    .map((o) => o.trim());

  // In development, allow localhost and LAN IPs (e.g. http://192.168.1.11:8080 for phone)
  const corsOrigin =
    process.env.NODE_ENV === 'production'
      ? allowedOrigins
      : (origin, callback) => {
          if (!origin || origin.startsWith('http://localhost:') || origin.startsWith('http://127.0.0.1:')) {
            callback(null, true);
          } else if (origin.startsWith('http://192.168.') || origin.startsWith('http://10.')) {
            callback(null, true);
          } else if (allowedOrigins.includes(origin)) {
            callback(null, true);
          } else {
            callback(new Error('Not allowed by CORS'));
          }
        };

  app.enableCors({ origin: corsOrigin, credentials: true });

  const port = configService.get('PORT') || 3000;
  await app.listen(port, '0.0.0.0');
  logger.log(`Server running on http://0.0.0.0:${port}`);
}
bootstrap();
