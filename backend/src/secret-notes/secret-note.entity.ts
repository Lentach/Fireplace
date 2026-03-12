// backend/src/secret-notes/secret-note.entity.ts
import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn } from 'typeorm';

@Entity('secret_notes')
export class SecretNote {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ unique: true, length: 64 })
  token: string;

  @Column({ type: 'text' })
  ciphertext: string;

  @Column({ type: 'timestamp' })
  expiresAt: Date;

  @Column({ nullable: true })
  creatorId: number;

  @CreateDateColumn()
  createdAt: Date;
}
