import { Global, Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MulterModule } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { LocalStorageService } from './local-storage.service';
import { MediaController } from './media.controller';
import { MediaCleanupService } from './media-cleanup.service';
import { Message } from '../messages/message.entity';

@Global()
@Module({
  imports: [
    ConfigModule,
    TypeOrmModule.forFeature([Message]),
    MulterModule.register({ storage: memoryStorage() }),
  ],
  controllers: [MediaController],
  providers: [
    LocalStorageService,
    MediaCleanupService,
    {
      provide: 'MEDIA_BASE_URL',
      inject: [ConfigService],
      useFactory: (cfg: ConfigService) =>
        cfg.get('MEDIA_BASE_URL', 'http://localhost:3000'),
    },
    {
      provide: 'MEDIA_DIR',
      inject: [ConfigService],
      useFactory: (cfg: ConfigService) => cfg.get('MEDIA_DIR', '/app/media'),
    },
  ],
  exports: [LocalStorageService, MediaCleanupService],
})
export class MediaModule {}
