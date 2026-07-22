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
      // `log` level (prod-visible) on purpose: the ONLY ground truth that the
      // ping path ran — per-send web-push logs are debug (prod-silent) by the
      // chat metadata-privacy contract, but a contact ping is not chat traffic.
      this.logger.log('Contact message stored; owner ping dispatched');
      this.pushNotificationsService.notifyContact(notifyId).catch((err) => {
        this.logger.warn(`Contact notify failed: ${err?.message ?? err}`);
      });
    } else {
      this.logger.log(
        'Contact message stored; ping skipped (CONTACT_NOTIFY_USER_ID unset)',
      );
    }
  }
}
