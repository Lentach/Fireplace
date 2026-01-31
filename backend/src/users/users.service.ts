import {
  Injectable,
  ConflictException,
  UnauthorizedException,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { User } from './user.entity';
import * as fs from 'fs/promises';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User)
    private usersRepo: Repository<User>,
  ) {}

  async create(email: string, password: string, username?: string): Promise<User> {
    // Sprawdzamy czy email jest już zajęty
    const existing = await this.usersRepo.findOne({ where: { email } });
    if (existing) {
      throw new ConflictException('Email already in use');
    }

    // Sprawdzamy czy username jest już zajęty (case-insensitive)
    if (username) {
      const existingUsername = await this.usersRepo
        .createQueryBuilder('user')
        .where('LOWER(user.username) = LOWER(:username)', { username })
        .getOne();
      if (existingUsername) {
        throw new ConflictException('Username already in use');
      }
    }

    // 10 rund bcrypt — dobry balans bezpieczeństwo/wydajność
    const hash = await bcrypt.hash(password, 10);

    const user = this.usersRepo.create({ email, password: hash, username });
    return this.usersRepo.save(user);
  }

  async findByEmail(email: string): Promise<User | null> {
    return this.usersRepo
      .createQueryBuilder('user')
      .where('LOWER(user.email) = LOWER(:email)', { email })
      .getOne();
  }

  async findById(id: number): Promise<User | null> {
    return this.usersRepo.findOne({ where: { id } });
  }

  async findByUsername(username: string): Promise<User | null> {
    return this.usersRepo
      .createQueryBuilder('user')
      .where('LOWER(user.username) = LOWER(:username)', { username })
      .getOne();
  }

  async updateProfilePicture(userId: number, url: string): Promise<User> {
    const user = await this.findById(userId);
    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Delete old profile picture if exists
    if (user.profilePictureUrl) {
      try {
        const oldPath = `.${user.profilePictureUrl}`;
        await fs.unlink(oldPath);
      } catch (error) {
        // File might not exist, continue
      }
    }

    user.profilePictureUrl = url;
    return this.usersRepo.save(user);
  }

  async resetPassword(
    userId: number,
    oldPassword: string,
    newPassword: string,
  ): Promise<void> {
    const user = await this.findById(userId);
    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Verify old password
    const isValidPassword = await bcrypt.compare(oldPassword, user.password);
    if (!isValidPassword) {
      throw new UnauthorizedException('Invalid old password');
    }

    // Hash new password
    const hash = await bcrypt.hash(newPassword, 10);
    user.password = hash;
    await this.usersRepo.save(user);
  }

  async deleteAccount(userId: number, password: string): Promise<void> {
    const user = await this.findById(userId);
    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Verify password
    const isValidPassword = await bcrypt.compare(password, user.password);
    if (!isValidPassword) {
      throw new UnauthorizedException('Invalid password');
    }

    // Delete profile picture if exists
    if (user.profilePictureUrl) {
      try {
        const picturePath = `.${user.profilePictureUrl}`;
        await fs.unlink(picturePath);
      } catch (error) {
        // File might not exist, continue
      }
    }

    // TypeORM cascades will delete related records
    await this.usersRepo.remove(user);
  }

  async updateActiveStatus(
    userId: number,
    activeStatus: boolean,
  ): Promise<User> {
    const user = await this.findById(userId);
    if (!user) {
      throw new NotFoundException('User not found');
    }

    user.activeStatus = activeStatus;
    return this.usersRepo.save(user);
  }
}
