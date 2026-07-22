// backend/src/contact/contact-message.entity.ts
import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
} from 'typeorm';

@Entity('contact_messages')
export class ContactMessage {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'text' })
  message: string;

  // Optional sender-supplied reply address (email, @handle, whatever they
  // typed) — free text on purpose, never used for automated mail.
  @Column({ type: 'varchar', length: 320, nullable: true })
  replyTo: string | null;

  @CreateDateColumn()
  createdAt: Date;
}
