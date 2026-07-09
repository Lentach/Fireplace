// backend/src/secret-notes/secret-note.entity.ts
import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  JoinColumn,
  ManyToOne,
} from 'typeorm';
import { User } from '../users/user.entity';

@Entity('secret_notes')
export class SecretNote {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ unique: true, length: 64 })
  token: string;

  @Column({ type: 'text' })
  ciphertext: string;

  @Column({ type: 'timestamp' })
  expiresAt: Date;

  @Column({ nullable: true })
  creatorId: number;

  // CASCADE, not SET NULL: account deletion destroys everything the account
  // created (privacy contract); notes expire within 12h regardless.
  @ManyToOne(() => User, { onDelete: 'CASCADE', nullable: true })
  @JoinColumn({ name: 'creatorId' })
  creator: User | null;

  @CreateDateColumn()
  createdAt: Date;
}
