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

@Entity('one_time_pre_keys')
@Index(['userId', 'used'])
@Index('UQ_one_time_pre_keys_user_key', ['userId', 'keyId'], { unique: true })
export class OneTimePreKey {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  userId: number;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: User;

  @Column()
  keyId: number;

  @Column('text')
  publicKey: string;

  /// Public identity key (base64) of the epoch that uploaded this OTP. Nullable
  /// for legacy/pre-migration rows; fetchPreKeyBundle only serves rows matching
  /// the current key bundle identity, so a null or superseded tag is never served.
  @Column({ type: 'text', nullable: true })
  identityPublicKey: string | null;

  @Column({ default: false })
  used: boolean;

  @CreateDateColumn()
  createdAt: Date;
}
