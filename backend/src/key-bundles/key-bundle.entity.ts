import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { User } from '../users/user.entity';

@Entity('key_bundles')
export class KeyBundle {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ unique: true })
  userId: number;

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
