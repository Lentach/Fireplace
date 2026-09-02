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

/**
 * One device's one-time pre-key (Phase 1, multi-device spec §4).
 *
 * keyId slots belong to a DEVICE, not to an account: two devices of one
 * account both mint keyId 0..N, and under the old account-wide unique key the
 * second device's upload silently took over the first device's slots. Indexes
 * mirror migration 0015 so `synchronize` cannot drop them in dev/CI.
 */
@Entity('one_time_pre_keys')
@Index(['userId', 'used'])
@Index('idx_one_time_pre_keys_user_device_used', ['userId', 'deviceId', 'used'])
@Index(
  'UQ_one_time_pre_keys_user_device_key',
  ['userId', 'deviceId', 'keyId'],
  { unique: true },
)
export class OneTimePreKey {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  userId: number;

  /** Per-account device number from 1; existing rows are device 1 (§8). */
  @Column({ default: 1 })
  deviceId: number;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: User;

  @Column()
  keyId: number;

  @Column('text')
  publicKey: string;

  /**
   * Public identity key (base64) of the epoch that uploaded this OTP. Nullable
   * for legacy/pre-migration rows; fetchPreKeyBundle only serves rows matching
   * the current key bundle identity, so a null or superseded tag is never served.
   */
  @Column({ type: 'text', nullable: true })
  identityPublicKey: string | null;

  @Column({ default: false })
  used: boolean;

  @CreateDateColumn()
  createdAt: Date;
}
