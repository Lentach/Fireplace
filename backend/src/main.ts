import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // ValidationPipe validates DTOs (e.g. checks if email is valid).
  // whitelist: true — strips properties not defined in the DTO (security).
  app.useGlobalPipes(new ValidationPipe({ whitelist: true }));

  // Allow cross-origin requests from the Flutter frontend
  app.enableCors({ origin: '*' });

  const port = process.env.PORT || 3000;
  await app.listen(port);
  console.log(`Server running on http://localhost:${port}`);
}
bootstrap();
