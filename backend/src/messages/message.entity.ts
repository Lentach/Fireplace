import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
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
  DRAWING = 'DRAWING',
  VOICE = 'VOICE',
}

@Entity('messages')
export class Message {
  @PrimaryGeneratedColumn()
  id: number;

  // Message content — plain text, no formatting in MVP
  @Column('text')
  content: string;

  @Column({
    type: 'enum',
    enum: MessageDeliveryStatus,
    default: MessageDeliveryStatus.SENT,
  })
  deliveryStatus: MessageDeliveryStatus;

  @Column({ type: 'timestamp', nullable: true })
  expiresAt: Date | null;

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
  @Column({ type: 'varchar', length: 500, default: '' })
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

  @ManyToOne(() => Conversation, { eager: false })
  @JoinColumn({ name: 'conversation_id' })
  conversation: Conversation;

  @CreateDateColumn()
  createdAt: Date;
}
