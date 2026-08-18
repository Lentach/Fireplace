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

@Entity()
@Index(['token'], { unique: true })
export class FcmToken {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  userId: number;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: User;

  @Column({ unique: true })
  token: string;

  /**
   * Which device registered this endpoint (Phase 1, spec §4). NULL for
   * endpoints registered before the column existed. Per-device targeting lets
   * a revoked device stop receiving without touching the others.
   */
  @Column({ type: 'int', nullable: true })
  deviceId: number | null;

  @Column({ default: 'web' })
  platform: string; // 'web' | 'android' | 'ios'

  @CreateDateColumn()
  createdAt: Date;
}
