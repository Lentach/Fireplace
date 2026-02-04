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
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { MessagesService } from './messages.service';
import { CloudinaryService } from '../cloudinary/cloudinary.service';
import { ConversationsService } from '../conversations/conversations.service';
import { UsersService } from '../users/users.service';
import { MessageType } from './message.entity';

@Controller('messages')
export class MessagesController {
  constructor(
    private messagesService: MessagesService,
    private cloudinaryService: CloudinaryService,
    private conversationsService: ConversationsService,
    private usersService: UsersService,
  ) {}

  @Post('image')
  @UseGuards(JwtAuthGuard)
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

    return {
      id: message.id,
      content: message.content,
      senderId: sender.id,
      senderEmail: sender.email,
      senderUsername: sender.username,
      conversationId: conversation.id,
      createdAt: message.createdAt,
      deliveryStatus: message.deliveryStatus,
      expiresAt: message.expiresAt,
      messageType: message.messageType,
      mediaUrl: message.mediaUrl,
    };
  }
}
