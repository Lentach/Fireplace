import {
  Column,
  CreateDateColumn,
  Entity,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

@Entity('key_bundles')
export class KeyBundle {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ unique: true })
  userId: number;

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
