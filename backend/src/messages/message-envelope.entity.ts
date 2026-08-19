import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { Message } from './message.entity';

/**
 * One recipient device's ciphertext for one message (Phase 2 T1, spec §4 +
 * §12 Stage-0 amendment (g)).
 *
 * Envelopes are RETAINED, not mailbox-deleted: they live exactly as long as
 * the message row, and the `messageId` FK's ON DELETE CASCADE is the SOLE
 * mechanism destroying never-fetched envelopes at the §5.6 disappearing
 * deadline — every landed destruction path is a DB DELETE on `messages`.
 *
 * Deliberately NO FK on (recipientUserId, recipientDeviceId) to `devices`:
 * envelopes outlive device-row lifecycle (decision record F3).
 *
 * The table starts EMPTY — pre-migration rows are served by the §5.3
 * device-gated legacy fallback, never backfilled. Write paths arrive in T4.
 *
 * Indexes mirror migration 0016 so `synchronize` (on everywhere but
 * production) cannot drop them in dev/CI. Prod truth is migration 0016.
 */
@Entity('message_envelopes')
@Index(
  'UQ_message_envelopes_message_recipient_device',
  ['messageId', 'recipientUserId', 'recipientDeviceId'],
  { unique: true },
)
@Index('idx_message_envelopes_recipient_device_message', [
  'recipientUserId',
  'recipientDeviceId',
  'messageId',
])
export class MessageEnvelope {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  messageId: number;

  // The load-bearing CASCADE (see class doc). Scalar messageId stays the API.
  @ManyToOne(() => Message, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'messageId' })
  message: Message;

  @Column()
  recipientUserId: number;

  /** Per-account device number from 1 — no FK to `devices` on purpose. */
  @Column()
  recipientDeviceId: number;

  /** Signal ciphertext ("{type}:{base64}"), pairwise to this device. */
  @Column('text')
  ciphertext: string;

  @Column({ type: 'timestamp', nullable: true })
  deliveredAt: Date | null;

  @Column({ type: 'timestamp', nullable: true })
  readAt: Date | null;

  @CreateDateColumn()
  createdAt: Date;
}
