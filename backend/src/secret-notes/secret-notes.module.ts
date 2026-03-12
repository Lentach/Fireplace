// backend/src/secret-notes/secret-notes.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SecretNote } from './secret-note.entity';
import { SecretNotesService } from './secret-notes.service';
import { SecretNotesController } from './secret-notes.controller';

@Module({
  imports: [TypeOrmModule.forFeature([SecretNote])],
  providers: [SecretNotesService],
  controllers: [SecretNotesController],
})
export class SecretNotesModule {}
