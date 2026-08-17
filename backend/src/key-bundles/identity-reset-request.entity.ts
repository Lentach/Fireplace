import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { User } from '../users/user.entity';

export type IdentityResetStatus = 'pending' | 'cancelled' | 'completed';

/**
 * One account-identity reset ceremony (Phase 0b, multi-device spec §6.2).
 *
 * States are TERMINAL: a row leaves 'pending' exactly once, to 'cancelled' or
 * 'completed'. Both transitions are conditional UPDATEs filtered on
 * status='pending', which is what serializes a cancel racing the expiry
 * commit — whichever statement lands first makes the other a no-op. A late
 * cancel after completion is therefore never an identity rollback.
 *
 * Prod truth is migration 0014.
 */
@Entity('identity_reset_requests')
@Index('idx_identity_reset_requests_user_status', ['userId', 'status'])
export class IdentityResetRequest {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  userId: number;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: User;

  @Column('text', { default: 'pending' })
  status: IdentityResetStatus;

  @CreateDateColumn()
  requestedAt: Date;

  /** When the delay elapses: 72 h normally, 1 h via a recovery key. */
  @Column({ type: 'timestamp' })
  deadlineAt: Date;

  @Column({ default: false })
  shortened: boolean;

  @Column({ type: 'timestamp', nullable: true })
  cancelledAt: Date | null;

  @Column({ type: 'timestamp', nullable: true })
  completedAt: Date | null;

  /**
   * Stamped when this completed reset is spent authorizing one identity
   * upload. Single-use by construction: the consuming UPDATE requires NULL.
   */
  @Column({ type: 'timestamp', nullable: true })
  consumedAt: Date | null;
}
