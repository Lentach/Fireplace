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
 * Durable record of a key-bundle identity replacement (Phase 0a takeover
 * alarm, multi-device spec §6.0). One row per detected churn; the detecting
 * pre-check in KeyBundlesService.upsertKeyBundle is deliberately racy, so
 * duplicates under concurrent uploads are acceptable. Prod truth is
 * migration 0013.
 */
@Entity('identity_change_audit')
@Index('idx_identity_change_audit_user_created', ['userId', 'createdAt'])
export class IdentityChangeAudit {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  userId: number;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: User;

  @Column('text')
  previousIdentityPublicKey: string;

  @Column('text')
  newIdentityPublicKey: string;

  @CreateDateColumn()
  createdAt: Date;
}
