import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { User } from '../users/user.entity';

/**
 * One device's public key bundle (Phase 1, multi-device spec §4).
 *
 * The UNIQUE key is `(userId, deviceId)`, NOT `userId`: with the old
 * account-wide constraint a second device's upload overwrote the first
 * device's bundle, so peers were handed keys that device could not read.
 * The index is mirrored from migration 0015 on purpose — TypeORM
 * `synchronize` (on everywhere but production) drops indexes the entity does
 * not declare.
 */
@Entity('key_bundles')
@Index('UQ_key_bundles_user_device', ['userId', 'deviceId'], { unique: true })
export class KeyBundle {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  userId: number;

  /** Per-account device number from 1; existing accounts are device 1 (§8). */
  @Column({ default: 1 })
  deviceId: number;

  // FK with CASCADE (migration 0002): account deletion destroys the bundle
  // even if a manual-cleanup path misses it. Scalar userId stays the API.
  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: User;

  @Column()
  registrationId: number;

  @Column('text')
  identityPublicKey: string;

  @Column()
  signedPreKeyId: number;

  @Column('text')
  signedPreKeyPublic: string;

  @Column('text')
  signedPreKeySignature: string;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
