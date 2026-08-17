import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { User } from '../users/user.entity';

/**
 * Optional recovery key for the identity reset ceremony (Phase 0b,
 * multi-device spec §6.2.1). One per account.
 *
 * The stored value is an Argon2id verifier hash and nothing else — never the
 * phrase, never a fast hash. Presenting a valid phrase SHORTENS the reset
 * delay from 72 h to 1 h; it never silences the notifications and never grants
 * an immediate identity replacement. Single-use: spent on a successful
 * presentation and invalidated by any completed reset.
 *
 * Prod truth is migration 0014.
 */
@Entity('recovery_keys')
export class RecoveryKey {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ unique: true })
  userId: number;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: User;

  /** Argon2id PHC string. Parameters are self-encoded for verification. */
  @Column('text')
  verifierHash: string;

  @CreateDateColumn()
  createdAt: Date;

  @Column({ type: 'timestamp', nullable: true })
  usedAt: Date | null;

  @Column({ default: 0 })
  failedAttempts: number;

  @Column({ type: 'timestamp', nullable: true })
  lockedUntil: Date | null;
}
