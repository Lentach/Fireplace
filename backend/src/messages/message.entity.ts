import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
  Index,
} from 'typeorm';
import { User } from '../users/user.entity';
import { Conversation } from '../conversations/conversation.entity';

export enum MessageDeliveryStatus {
  SENDING = 'SENDING',
  SENT = 'SENT',
  DELIVERED = 'DELIVERED',
  READ = 'READ',
}

export enum MessageType {
  TEXT = 'TEXT',
  PING = 'PING',
  IMAGE = 'IMAGE',
  VOICE = 'VOICE',
  GIF = 'GIF',
  FILE = 'FILE',
  VIDEO = 'VIDEO',
}

@Index('idx_messages_conv_created', ['conversation', 'createdAt'])
// A duplicate token from one sender is a RETRY of a send the server already
// committed, never a second message. Mirrored from migration 0015 so
// `synchronize` (on everywhere but production) cannot drop it in dev/CI.
@Index('UQ_messages_sender_send_token', ['sender', 'sendToken'], {
  unique: true,
  where: '"sendToken" IS NOT NULL',
})
@Entity('messages')
export class Message {
  @PrimaryGeneratedColumn()
  id: number;

  // Message content — plaintext or "[encrypted]" placeholder when E2E encrypted
  @Column('text')
  content: string;

  // Base64-encoded Signal Protocol ciphertext. Null for unencrypted messages.
  @Column({ type: 'text', nullable: true, default: null })
  encryptedContent: string | null;

  @Column({
    type: 'enum',
    enum: MessageDeliveryStatus,
    default: MessageDeliveryStatus.SENT,
  })
  deliveryStatus: MessageDeliveryStatus;

  @Column({ type: 'timestamp', nullable: true })
  expiresAt: Date | null;

  /** TTL frozen at send (seconds); countdown starts on read. Null = grandfathered or non-disappearing. */
  @Column({ type: 'int', nullable: true })
  disappearAfterSeconds: number | null;

  @Column({
    type: 'enum',
    enum: MessageType,
    default: MessageType.TEXT,
  })
  messageType: MessageType;

  @Column({ type: 'text', nullable: true })
  mediaUrl: string | null;

  @Column({ type: 'int', nullable: true })
  mediaDuration: number | null;

  /** Comma-separated user IDs who "deleted for me" — hidden from their view only */
  @Column({ type: 'text', default: '' })
  hiddenByUserIds: string;

  /** JSON: {"👍":[1,3],"❤️":[2]} — emoji reactions by userId */
  @Column({ type: 'text', nullable: true, default: null })
  reactions: string | null;

  @Column({ type: 'text', nullable: true, default: null })
  linkPreviewUrl: string | null;

  @Column({ type: 'text', nullable: true, default: null })
  linkPreviewTitle: string | null;

  @Column({ type: 'text', nullable: true, default: null })
  linkPreviewImageUrl: string | null;

  /** ID of the message being replied to (same conversation). */
  @Column({ type: 'int', nullable: true })
  replyToMessageId: number | null;

  @ManyToOne(() => Message, { nullable: true, eager: false })
  @JoinColumn({ name: 'reply_to_message_id' })
  replyTo: Message | null;

  @ManyToOne(() => User, { eager: true })
  @JoinColumn({ name: 'sender_id' })
  sender: User;

  /**
   * Which of the sender's devices produced this message (Phase 1, spec §5.4).
   * NULL on pre-migration rows and on legacy-client sends. Self-sync scoping
   * reads this — "is this mine?" becomes "is this MY DEVICE's?" — so a
   * sender's other device can decrypt its own account's message.
   */
  @Column({ type: 'int', nullable: true })
  originDeviceId: number | null;

  /**
   * Client-generated token making a send idempotent across a lost ack: the
   * sending device holds the ONLY plaintext copy until the ack lands, so a
   * retry must match the committed row rather than create a second one.
   * UNIQUE per sender (partial index, migration 0015).
   */
  @Column({ type: 'text', nullable: true })
  sendToken: string | null;

  @ManyToOne(() => Conversation, { eager: false })
  @JoinColumn({ name: 'conversation_id' })
  conversation: Conversation;

  @CreateDateColumn()
  createdAt: Date;

  /** Timestamp of the last in-place edit (E2E re-encryption). Null = never edited. */
  @Column({ type: 'timestamp', nullable: true })
  editedAt: Date | null;
}
