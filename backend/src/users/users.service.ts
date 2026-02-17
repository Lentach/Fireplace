import {
  Injectable,
  ConflictException,
  UnauthorizedException,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { User } from './user.entity';
import { CloudinaryService } from '../cloudinary/cloudinary.service';
import { Conversation } from '../conversations/conversation.entity';
import { Message } from '../messages/message.entity';
import { FriendRequest } from '../friends/friend-request.entity';

@Injectable()
export class UsersService {
  private readonly auditLogger = new Logger('Audit');

  constructor(
    @InjectRepository(User)
    private usersRepo: Repository<User>,
    @InjectRepository(Conversation)
    private convRepo: Repository<Conversation>,
    @InjectRepository(Message)
    private messageRepo: Repository<Message>,
    @InjectRepository(FriendRequest)
    private friendRequestRepo: Repository<FriendRequest>,
    private cloudinaryService: CloudinaryService,
  ) {}

  async create(
    email: string,
    password: string,
    username?: string,
  ): Promise<User> {
    // Check if email is already taken
    const existing = await this.usersRepo.findOne({ where: { email } });
    if (existing) {
      throw new ConflictException('Email already in use');
    }

    // Check if username is already taken (case-insensitive)
    if (username) {
      const existingUsername = await this.usersRepo
        .createQueryBuilder('user')
        .where('LOWER(user.username) = LOWER(:username)', { username })
        .getOne();
      if (existingUsername) {
        throw new ConflictException('Username already in use');
      }
    }

    // 10 bcrypt rounds — good balance of security and performance
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

  async updateProfilePicture(
    userId: number,
    secureUrl: string,
    publicId: string,
  ): Promise<User> {
    const user = await this.findById(userId);
    if (!user) {
      throw new NotFoundException('User not found');
    }

    // Delete old Cloudinary avatar only if different publicId (overwrite uses same id)
    if (user.profilePicturePublicId && user.profilePicturePublicId !== publicId) {
      await this.cloudinaryService.deleteAvatar(user.profilePicturePublicId);
    }

    user.profilePictureUrl = secureUrl;
    user.profilePicturePublicId = publicId;
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
    this.auditLogger.log(`resetPassword success userId=${userId}`);
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

    // Delete Cloudinary avatar if exists
    if (user.profilePicturePublicId) {
      await this.cloudinaryService.deleteAvatar(user.profilePicturePublicId);
    }

    // Delete dependent data first: messages → conversations → friend_requests (User entity has no cascade)
    const conversations = await this.convRepo.find({
      where: [
        { userOne: { id: userId } },
        { userTwo: { id: userId } },
      ],
    });

    for (const conv of conversations) {
      await this.messageRepo.delete({ conversation: { id: conv.id } });
      await this.convRepo.delete({ id: conv.id });
    }

    const friendRequests = await this.friendRequestRepo.find({
      where: [
        { sender: { id: userId } },
        { receiver: { id: userId } },
      ],
    });
    if (friendRequests.length > 0) {
      await this.friendRequestRepo.remove(friendRequests);
    }

    await this.usersRepo.remove(user);
    this.auditLogger.log(`deleteAccount success userId=${userId} email=${user.email}`);
  }
}
