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

@Entity('messages')
export class Message {
  @PrimaryGeneratedColumn()
  id: number;

  // Treść wiadomości — zwykły tekst, bez formatowania w MVP
  @Column('text')
  content: string;

  @ManyToOne(() => User, { eager: true })
  @JoinColumn({ name: 'sender_id' })
  sender: User;

  @ManyToOne(() => Conversation, { eager: false })
  @JoinColumn({ name: 'conversation_id' })
  conversation: Conversation;

  @CreateDateColumn()
  createdAt: Date;
}
