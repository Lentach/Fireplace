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
import { MessagesService } from './messages.service';
import { CloudinaryService } from '../cloudinary/cloudinary.service';
import { ConversationsService } from '../conversations/conversations.service';
import { UsersService } from '../users/users.service';
import { ChatValidationService } from '../chat/services/chat-validation.service';
import { LinkPreviewService } from '../chat/services/link-preview.service';
import { MessageType } from './message.entity';
import { MessageMapper } from './message.mapper';
import { UploadImageDto } from './dto/upload-image.dto';
import { UploadVoiceDto } from './dto/upload-voice.dto';
import { validateDto } from '../chat/utils/dto.validator';

@Controller('messages')
export class MessagesController {
  constructor(
    private messagesService: MessagesService,
    private cloudinaryService: CloudinaryService,
    private conversationsService: ConversationsService,
    private usersService: UsersService,
    private chatValidationService: ChatValidationService,
    private linkPreviewService: LinkPreviewService,
  ) {}

  @Post('image')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 10, ttl: 60000 } }) // 10 uploads per minute
  @UseInterceptors(FileInterceptor('file'))
  async uploadImageMessage(
    @UploadedFile() file: Express.Multer.File,
    @Body() body: Record<string, unknown>,
    @Request() req,
  ) {
    if (!file) {
      throw new BadRequestException('No file uploaded');
    }

    const allowedMimeTypes = ['image/jpeg', 'image/jpg', 'image/png'];
    if (!allowedMimeTypes.includes(file.mimetype)) {
      throw new BadRequestException('Only JPEG/PNG images are allowed');
    }

    const maxSize = 5 * 1024 * 1024; // 5 MB
    if (file.size > maxSize) {
      throw new BadRequestException('File size must not exceed 5 MB');
    }

    const dto = validateDto(UploadImageDto, body);
    const sender = req.user;
    const recipient = await this.usersService.findById(dto.recipientId);
    if (!recipient) {
      throw new BadRequestException('Recipient not found');
    }

    const validation = await this.chatValidationService.validateCanMessage(
      sender.id,
      recipient.id,
    );
    if (!validation.valid) {
      throw new BadRequestException(validation.error);
    }

    const uploadResult = await this.cloudinaryService.uploadImage(
      sender.id,
      file.buffer,
      file.mimetype,
    );

    const conversation = await this.conversationsService.findOrCreate(
      sender,
      recipient,
    );

    let expiresAt: Date | null = null;
    if (dto.expiresIn != null && dto.expiresIn > 0) {
      expiresAt = new Date(Date.now() + dto.expiresIn * 1000);
    }

    const message = await this.messagesService.create('', sender, conversation, {
      messageType: MessageType.IMAGE,
      mediaUrl: uploadResult.secureUrl,
      expiresAt,
    });

    return MessageMapper.toPayload(message, {
      conversationId: conversation.id,
    });
  }

  @Post('voice')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 10, ttl: 60000 } })
  @UseInterceptors(
    FileInterceptor('audio', {
      limits: { fileSize: 10 * 1024 * 1024 },
      fileFilter: (req, file, cb) => {
        const allowedMimes = [
          'audio/aac', 'audio/mp4', 'audio/m4a', 'audio/mpeg',
          'audio/webm', 'audio/wav', 'audio/wave', 'audio/x-wav',
        ];
        if (!allowedMimes.includes(file.mimetype)) {
          return cb(new BadRequestException('Invalid audio format'), false);
        }
        cb(null, true);
      },
    }),
  )
  async uploadVoiceMessage(
    @UploadedFile() file: Express.Multer.File,
    @Body() body: Record<string, unknown>,
    @Request() req?,
  ) {
    if (!file) {
      throw new BadRequestException('No audio file uploaded');
    }
    const dto = validateDto(UploadVoiceDto, body);
    const sender = req.user;
    const recipient = await this.usersService.findById(dto.recipientId);
    if (!recipient) {
      throw new BadRequestException('Recipient not found');
    }

    const validation = await this.chatValidationService.validateCanMessage(
      sender.id,
      recipient.id,
    );
    if (!validation.valid) {
      throw new BadRequestException(validation.error);
    }

    const result = await this.cloudinaryService.uploadVoiceMessage(
      sender.id,
      file.buffer,
      file.mimetype,
      dto.expiresIn,
    );

    return {
      mediaUrl: result.secureUrl,
      publicId: result.publicId,
      duration: result.duration || dto.duration,
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
