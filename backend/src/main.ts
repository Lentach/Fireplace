import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  const logger = new Logger('Bootstrap');
  const configService = app.get(ConfigService);

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
  app.enableCors({ origin: allowedOrigins });

  const port = configService.get('PORT') || 3000;
  await app.listen(port);
  logger.log(`Server running on http://localhost:${port}`);
}
bootstrap();
