// backend/src/contact/contact.service.ts
import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { ContactMessage } from './contact-message.entity';
import { PushNotificationsService } from '../push-notifications/push-notifications.service';

@Injectable()
export class ContactService {
  private readonly logger = new Logger(ContactService.name);

  constructor(
    @InjectRepository(ContactMessage)
    private readonly contactRepo: Repository<ContactMessage>,
    private readonly pushNotificationsService: PushNotificationsService,
  ) {}

  async create(message: string, replyTo: string | null): Promise<void> {
    await this.contactRepo.save(
      this.contactRepo.create({ message, replyTo }),
    );

    // Fire-and-forget owner ping: Web Push to the account named by
    // CONTACT_NOTIFY_USER_ID (unset = store-only). A push failure must never
    // fail the visitor's submission — the row is already saved.
    const notifyId = Number(process.env.CONTACT_NOTIFY_USER_ID);
    if (Number.isInteger(notifyId) && notifyId > 0) {
      this.pushNotificationsService.notifyContact(notifyId).catch((err) => {
        this.logger.warn(`Contact notify failed: ${err?.message ?? err}`);
      });
    }
  }
}
