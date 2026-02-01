import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
} from 'typeorm';

@Entity('users')
export class User {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ unique: true })
  email: string;

  @Column({ unique: true, nullable: true })
  username: string;

  // Password stored as bcrypt hash — never plain text
  @Column()
  password: string;

  @Column({ nullable: true })
  profilePictureUrl: string;

  @Column({ nullable: true })
  profilePicturePublicId: string;

  @Column({ default: true })
  activeStatus: boolean;

  @CreateDateColumn()
  createdAt: Date;
}
