// backend/src/contact/contact-push-subscription.entity.ts
import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
} from 'typeorm';

// Push subscriptions for the OWNER's contact inbox page (/contact/inbox).
// Deliberately NOT tied to any user account: the inbox outlives accounts.
@Entity('contact_push_subscriptions')
export class ContactPushSubscription {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'text', unique: true })
  endpoint: string;

  @Column({ type: 'text' })
  p256dh: string;

  @Column({ type: 'text' })
  auth: string;

  @CreateDateColumn()
  createdAt: Date;
}
