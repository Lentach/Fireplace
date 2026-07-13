import { Column, CreateDateColumn, Entity, JoinColumn, ManyToOne, PrimaryGeneratedColumn, Unique, UpdateDateColumn } from 'typeorm';
import { Conversation } from '../conversations/conversation.entity';
import { User } from '../users/user.entity';

@Entity('conversation_notification_preferences')
@Unique(['viewerId', 'conversationId'])
export class ConversationNotificationPreference {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  viewerId: number;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'viewerId' })
  viewer: User;

  @Column()
  conversationId: number;

  @ManyToOne(() => Conversation, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'conversationId' })
  conversation: Conversation;

  /** Null means this viewer muted the conversation indefinitely. */
  @Column({ type: 'timestamp', nullable: true })
  mutedUntil: Date | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
