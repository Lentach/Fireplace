import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { NestExpressApplication } from '@nestjs/platform-express';
import { join } from 'path';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);

  // ValidationPipe validates DTOs (e.g. checks if email is valid).
  // whitelist: true — strips properties not defined in the DTO (security).
  app.useGlobalPipes(new ValidationPipe({ whitelist: true }));

  // Serve static files (frontend) from the public directory
  app.useStaticAssets(join(__dirname, '..', 'src', 'public'));

  const port = process.env.PORT || 3000;
  await app.listen(port);
  console.log(`Server running on http://localhost:${port}`);
}
bootstrap();
