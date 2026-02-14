import {
  Entity,
  PrimaryGeneratedColumn,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
  Column,
} from 'typeorm';
import { User } from '../users/user.entity';

// A conversation links two users.
// In this MVP there are no groups — 1-on-1 chat only.
@Entity('conversations')
export class Conversation {
  @PrimaryGeneratedColumn()
  id: number;

  @ManyToOne(() => User, { eager: true })
  @JoinColumn({ name: 'user_one_id' })
  userOne: User;

  @ManyToOne(() => User, { eager: true })
  @JoinColumn({ name: 'user_two_id' })
  userTwo: User;

  @CreateDateColumn()
  createdAt: Date;

  @Column({ type: 'int', nullable: true, default: 86400 })
  disappearingTimer: number | null; // Timer in seconds, default 1 day (86400s)
}
