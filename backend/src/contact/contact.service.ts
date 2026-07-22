// backend/src/contact/contact.service.ts
import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { createHash, timingSafeEqual } from 'crypto';
import { ContactMessage } from './contact-message.entity';
import { ContactPushSubscription } from './contact-push-subscription.entity';
import { PushNotificationsService } from '../push-notifications/push-notifications.service';

@Injectable()
export class ContactService {
  private readonly logger = new Logger(ContactService.name);

  constructor(
    @InjectRepository(ContactMessage)
    private readonly contactRepo: Repository<ContactMessage>,
    @InjectRepository(ContactPushSubscription)
    private readonly subRepo: Repository<ContactPushSubscription>,
    private readonly pushNotificationsService: PushNotificationsService,
  ) {}

  // Inbox auth: one long random key (CONTACT_INBOX_KEY env, hex) shared via
  // the owner's bookmarked URL. Hash both sides before timingSafeEqual so the
  // comparison is constant-time regardless of attacker-controlled length.
  inboxKeyValid(key: string | undefined): boolean {
    const expected = process.env.CONTACT_INBOX_KEY;
    if (!expected || expected.length < 32 || !key) return false;
    return timingSafeEqual(
      createHash('sha256').update(key).digest(),
      createHash('sha256').update(expected).digest(),
    );
  }

  async create(message: string, replyTo: string | null): Promise<void> {
    await this.contactRepo.save(this.contactRepo.create({ message, replyTo }));

    // Fire-and-forget doorbells — a push failure must never fail the visitor's
    // submission (the row is already saved). Two independent channels:
    // 1) legacy: Web Push to the CONTACT_NOTIFY_USER_ID account (optional);
    // 2) inbox subscriptions (account-independent, carry a content preview —
    //    the inbox is the owner's private page, so previews are fine there).
    const notifyId = Number(process.env.CONTACT_NOTIFY_USER_ID);
    if (Number.isInteger(notifyId) && notifyId > 0) {
      // `log` level (prod-visible) on purpose: ground truth that the ping path
      // ran — per-send web-push logs are debug (prod-silent) by the chat
      // metadata-privacy contract, but a contact ping is not chat traffic.
      this.logger.log('Contact message stored; owner ping dispatched');
      this.pushNotificationsService.notifyContact(notifyId).catch((err) => {
        this.logger.warn(`Contact notify failed: ${err?.message ?? err}`);
      });
    } else {
      this.logger.log(
        'Contact message stored; account ping skipped (CONTACT_NOTIFY_USER_ID unset)',
      );
    }
    this.notifyInbox(message).catch((err) => {
      this.logger.warn(`Inbox notify failed: ${err?.message ?? err}`);
    });
  }

  async listMessages(): Promise<ContactMessage[]> {
    return this.contactRepo.find({ order: { id: 'DESC' }, take: 200 });
  }

  async subscribe(endpoint: string, p256dh: string, auth: string): Promise<void> {
    // Upsert on endpoint: re-subscribing from the same browser refreshes keys.
    await this.subRepo.upsert({ endpoint, p256dh, auth }, ['endpoint']);
  }

  private async notifyInbox(message: string): Promise<void> {
    const subs = await this.subRepo.find();
    if (!subs.length) return;
    const key = process.env.CONTACT_INBOX_KEY ?? '';
    const preview =
      message.length > 120 ? `${message.slice(0, 119)}…` : message;
    const body = {
      title: 'Contact form',
      body: preview,
      url: `/contact/inbox?key=${key}`,
    };
    let delivered = 0;
    for (const sub of subs) {
      const result = await this.pushNotificationsService.sendRawWebPush(
        sub,
        body,
      );
      if (result === 'ok') delivered++;
      if (result === 'stale') await this.subRepo.delete({ id: sub.id });
    }
    this.logger.log(
      `Inbox ping: ${delivered}/${subs.length} subscription(s) delivered`,
    );
  }
}
