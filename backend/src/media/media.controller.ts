import {
  Controller,
  Post,
  Get,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  Body,
  Request,
  Res,
  Param,
  BadRequestException,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Throttle } from '@nestjs/throttler';
import * as path from 'path';
import type { Response } from 'express';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { LocalStorageService } from './local-storage.service';
import { UploadMediaDto } from './dto/upload-media.dto';
import { validateDto } from '../chat/utils/dto.validator';
import { validateAvatarMagicBytes } from './magic-bytes.validator';

// Media is served directly by Node by default. Set MEDIA_X_ACCEL_REDIRECT=true ONLY when
// nginx is configured with an internal `/internal/media/` location to offload file serving;
// otherwise the response would be an empty 200 (the cause of "all media broken" in prod).
const useXAccel = process.env.MEDIA_X_ACCEL_REDIRECT === 'true';
const mediaDir = process.env.MEDIA_DIR ?? '/app/media';

@Controller('media')
export class MediaController {
  constructor(private storage: LocalStorageService) {}

  @Post('upload')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 20, ttl: 60000 } })
  @UseInterceptors(
    FileInterceptor('file', { limits: { fileSize: 21 * 1024 * 1024 } }),
  )
  async upload(
    @UploadedFile() file: Express.Multer.File,
    @Body() body: Record<string, unknown>,
    @Request() req: { user: { id: number } },
  ) {
    if (!file) throw new BadRequestException('No file uploaded');
    const dto = validateDto(UploadMediaDto, body);
    const userId = req.user.id;

    if (dto.mediaType === 'voice') {
      const result = await this.storage.uploadVoiceMessage(
        userId,
        file.buffer,
        file.mimetype,
        dto.duration ?? 0,
        dto.expiresIn,
      );
      return { mediaUrl: result.secureUrl, mediaDuration: result.duration };
    }
    if (dto.mediaType === 'file') {
      const result = await this.storage.uploadRawFile(
        userId,
        file.buffer,
        file.mimetype,
        dto.fileName ?? file.originalname,
      );
      return {
        mediaUrl: result.secureUrl,
        fileName: dto.fileName ?? file.originalname,
      };
    }
    if (dto.mediaType === 'video') {
      // Same opaque encrypted-blob msgs/ path as 'file' — the server never
      // inspects the bytes; duration is client-reported seconds, echoed back.
      const result = await this.storage.uploadRawFile(
        userId,
        file.buffer,
        file.mimetype,
      );
      return { mediaUrl: result.secureUrl, mediaDuration: dto.duration ?? 0 };
    }
    if (dto.mediaType === 'avatar') {
      validateAvatarMagicBytes(file.buffer);
      const result = await this.storage.uploadAvatar(
        userId,
        file.buffer,
        file.mimetype,
      );
      return { mediaUrl: result.secureUrl };
    }
    const result = await this.storage.uploadImage(
      userId,
      file.buffer,
      file.mimetype,
    );
    return { mediaUrl: result.secureUrl };
  }

  @Get('avatars/:filename')
  @Throttle({ default: { limit: 60, ttl: 60000 } })
  async serveAvatars(
    @Param('filename') filename: string,
    @Res() res: Response,
  ) {
    const safeFilename = path.basename(filename);
    if (safeFilename !== filename) throw new BadRequestException('Invalid filename');
    if (!useXAccel) {
      return res.sendFile(path.join(mediaDir, 'avatars', safeFilename));
    }
    res.setHeader('X-Accel-Redirect', `/internal/media/avatars/${safeFilename}`);
    res.status(200).send();
  }

  @Get('msgs/:filename')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 60, ttl: 60000 } })
  async serveMsgs(@Param('filename') filename: string, @Res() res: Response) {
    const safeFilename = path.basename(filename);
    if (safeFilename !== filename) throw new BadRequestException('Invalid filename');
    if (!useXAccel) {
      return res.sendFile(path.join(mediaDir, 'msgs', safeFilename));
    }
    res.setHeader('X-Accel-Redirect', `/internal/media/msgs/${safeFilename}`);
    res.status(200).send();
  }
}
