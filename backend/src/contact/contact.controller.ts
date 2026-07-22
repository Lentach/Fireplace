// backend/src/contact/contact.controller.ts
import {
  BadRequestException,
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Post,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ContactService } from './contact.service';
import { CreateContactDto } from './dto/create-contact.dto';

@Controller('contact')
export class ContactController {
  constructor(private readonly contactService: ContactService) {}

  // Public (the landing page has no auth). Abuse surface is bounded by the
  // per-IP throttle + honeypot + length caps; worst case is rows in a table.
  @Post()
  @Throttle({ default: { limit: 5, ttl: 900000 } }) // 5 per 15 min per IP
  @HttpCode(HttpStatus.NO_CONTENT)
  async create(@Body() dto: CreateContactDto): Promise<void> {
    // Honeypot filled -> bot. Pretend success so it learns nothing.
    if (dto.website) return;

    const message = dto.message.trim();
    if (!message) throw new BadRequestException('message must not be empty');

    const replyTo = dto.replyTo?.trim() || null;
    await this.contactService.create(message, replyTo);
  }
}
