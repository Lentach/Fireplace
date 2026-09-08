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
 * Prod truth is migration 0014; the backup columns are migration 0017.
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

  /**
   * Identity key backup (amendment (lxxviii)): AES-256-GCM blob sealed under
   * a key derived from the phrase — base64(iv12 || ct). The server can never
   * open it; the phrase is the key. Null until the client uploads one.
   */
  @Column({ type: 'text', nullable: true })
  backupBlob: string | null;

  /** base64 PBKDF2 salt the blob's key was derived with. */
  @Column({ type: 'text', nullable: true })
  backupSalt: string | null;

  /** PBKDF2-HMAC-SHA256 iteration count (client-chosen, bounded by the DTO). */
  @Column({ type: 'int', nullable: true })
  backupIterations: number | null;

  /** Blob format version; 1 is the only one defined. */
  @Column({ type: 'int', nullable: true })
  backupVersion: number | null;

  @Column({ type: 'timestamp', nullable: true })
  backupUpdatedAt: Date | null;
}
