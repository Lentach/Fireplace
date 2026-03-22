import {
  Controller,
  Post,
  UseGuards,
  Body,
  BadRequestException,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { LinkPreviewService } from '../chat/services/link-preview.service';

@Controller('messages')
export class MessagesController {
  constructor(private linkPreviewService: LinkPreviewService) {}

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
