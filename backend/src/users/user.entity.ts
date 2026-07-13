import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Unique,
  OneToMany,
} from 'typeorm';
import { ProfilePhoto } from './profile-photo.entity';

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
  profilePictureUrl: string | null;

  @Column({ nullable: true })
  profilePicturePublicId: string | null;

  @Column({ length: 80, nullable: true })
  about: string | null;

  @OneToMany(() => ProfilePhoto, (photo) => photo.user)
  profilePhotos: ProfilePhoto[];


  @CreateDateColumn()
  createdAt: Date;

  @Column({ type: 'timestamp', nullable: true })
  passwordChangedAt: Date | null;
}
