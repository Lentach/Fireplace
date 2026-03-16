import {
  Controller,
  Post,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  Body,
  Request,
  BadRequestException,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Throttle } from '@nestjs/throttler';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CloudinaryService } from '../cloudinary/cloudinary.service';
import { LinkPreviewService } from '../chat/services/link-preview.service';
import { UploadMediaDto } from './dto/upload-media.dto';
import { validateDto } from '../chat/utils/dto.validator';

@Controller('messages')
export class MessagesController {
  constructor(
    private cloudinaryService: CloudinaryService,
    private linkPreviewService: LinkPreviewService,
  ) {}

  @Post('upload-media')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  @UseInterceptors(FileInterceptor('file', {
    limits: { fileSize: 10 * 1024 * 1024 },
  }))
  async uploadMedia(
    @UploadedFile() file: Express.Multer.File,
    @Body() body: Record<string, unknown>,
    @Request() req,
  ) {
    if (!file) {
      throw new BadRequestException('No file uploaded');
    }

    const dto = validateDto(UploadMediaDto, body);

    if (dto.type === 'image' || dto.type === 'gif') {
      const allowedMimeTypes = dto.type === 'gif'
        ? ['image/gif']
        : ['image/jpeg', 'image/jpg', 'image/png'];
      const label = dto.type === 'gif' ? 'GIF' : 'JPEG/PNG';
      if (!allowedMimeTypes.includes(file.mimetype)) {
        throw new BadRequestException(`Only ${label} images are allowed`);
      }
      if (file.size > 5 * 1024 * 1024) {
        throw new BadRequestException('Image size must not exceed 5 MB');
      }
      const result = await this.cloudinaryService.uploadImage(
        req.user.id,
        file.buffer,
        file.mimetype,
      );
      return { mediaUrl: result.secureUrl };
    }

    if (dto.type === 'file') {
      const allowedMimeTypes = [
        'application/pdf',
        'application/msword', // .doc
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document', // .docx
        'application/vnd.ms-excel', // .xls
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', // .xlsx
        'text/plain',
        'text/csv',
      ];
      if (!allowedMimeTypes.includes(file.mimetype)) {
        throw new BadRequestException(
          'Allowed document types: PDF, DOC, DOCX, XLS, XLSX, TXT, CSV',
        );
      }
      if (file.size > 10 * 1024 * 1024) {
        throw new BadRequestException('File size must not exceed 10 MB');
      }
      const result = await this.cloudinaryService.uploadRawFile(
        req.user.id,
        file.buffer,
        file.mimetype,
        file.originalname,
      );
      return {
        mediaUrl: result.secureUrl,
        fileName: file.originalname || 'document',
      };
    }

    // voice
    const allowedAudioMimes = [
      'audio/aac', 'audio/mp4', 'audio/m4a', 'audio/mpeg',
      'audio/webm', 'audio/wav', 'audio/wave', 'audio/x-wav',
    ];
    if (!allowedAudioMimes.includes(file.mimetype)) {
      throw new BadRequestException('Invalid audio format');
    }
    const result = await this.cloudinaryService.uploadVoiceMessage(
      req.user.id,
      file.buffer,
      file.mimetype,
      dto.expiresIn,
    );
    return {
      mediaUrl: result.secureUrl,
      mediaDuration: result.duration || dto.duration,
    };
  }

  @Post('link-preview')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 30, ttl: 60000 } })
  async fetchLinkPreview(@Body() body: { text: string }) {
    const text = body?.text;
    if (!text || typeof text !== 'string') {
      throw new BadRequestException('text is required');
    }
    const preview = await this.linkPreviewService.fetchPreview(text);
    return preview ?? {};
  }
}
