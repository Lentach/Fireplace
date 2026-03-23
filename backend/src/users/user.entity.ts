import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Unique,
} from 'typeorm';

@Entity('users')
@Unique(['username', 'tag'])
export class User {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  username: string;

  @Column({ length: 4, default: '0000' })
  tag: string;

  // Password stored as bcrypt hash — never plain text
  @Column()
  password: string;

  @Column({ nullable: true })
  profilePictureUrl: string;

  @Column({ nullable: true })
  profilePicturePublicId: string;

  @CreateDateColumn()
  createdAt: Date;

  @Column({ type: 'timestamp', nullable: true })
  passwordChangedAt: Date | null;
}
