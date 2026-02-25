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
import { FriendsService } from '../friends/friends.service';
import { MessageType } from './message.entity';
import { MessageMapper } from './message.mapper';

@Controller('messages')
export class MessagesController {
  constructor(
    private messagesService: MessagesService,
    private cloudinaryService: CloudinaryService,
    private conversationsService: ConversationsService,
    private usersService: UsersService,
    private friendsService: FriendsService,
  ) {}

  @Post('image')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 10, ttl: 60000 } }) // 10 uploads per minute
  @UseInterceptors(FileInterceptor('file'))
  async uploadImageMessage(
    @UploadedFile() file: Express.Multer.File,
    @Body('recipientId') recipientId: string,
    @Body('expiresIn') expiresIn: string,
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

    const sender = req.user;
    const recipient = await this.usersService.findById(parseInt(recipientId));
    if (!recipient) {
      throw new BadRequestException('Recipient not found');
    }

    // Verify friend relationship
    const areFriends = await this.friendsService.areFriends(
      sender.id,
      recipient.id,
    );
    if (!areFriends) {
      throw new BadRequestException('You can only send images to friends');
    }

    // Upload to Cloudinary
    const uploadResult = await this.cloudinaryService.uploadImage(
      sender.id,
      file.buffer,
      file.mimetype,
    );

    // Find or create conversation
    const conversation = await this.conversationsService.findOrCreate(
      sender,
      recipient,
    );

    // Calculate expiresAt
    let expiresAt: Date | null = null;
    if (expiresIn && parseInt(expiresIn) > 0) {
      const seconds = parseInt(expiresIn);
      expiresAt = new Date(Date.now() + seconds * 1000);
    }

    // Create image message
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
    @Body('duration') duration: string,
    @Body('recipientId') recipientId: string,
    @Body('expiresIn') expiresIn?: string,
    @Request() req?,
  ) {
    const sender = req.user;
    const recipientIdNum = parseInt(recipientId, 10);
    if (!recipientId || isNaN(recipientIdNum)) {
      throw new BadRequestException('recipientId is required');
    }

    const recipient = await this.usersService.findById(recipientIdNum);
    if (!recipient) {
      throw new BadRequestException('Recipient not found');
    }

    const areFriends = await this.friendsService.areFriends(sender.id, recipient.id);
    if (!areFriends) {
      throw new BadRequestException('You can only send voice messages to friends');
    }

    const durationNum = parseInt(duration, 10);
    const expiresInNum = expiresIn ? parseInt(expiresIn, 10) : undefined;

    const result = await this.cloudinaryService.uploadVoiceMessage(
      sender.id,
      file.buffer,
      file.mimetype,
      expiresInNum,
    );

    return {
      mediaUrl: result.secureUrl,
      publicId: result.publicId,
      duration: result.duration || durationNum,
    };
  }
}
