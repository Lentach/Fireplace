import {
  Injectable,
  ConflictException,
  UnauthorizedException,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { User } from './user.entity';
import { LocalStorageService } from '../media/local-storage.service';
import { Conversation } from '../conversations/conversation.entity';
import { Message } from '../messages/message.entity';
import { FriendRequest } from '../friends/friend-request.entity';
import { FcmTokensService } from '../fcm-tokens/fcm-tokens.service';
import { KeyBundlesService } from '../key-bundles/key-bundles.service';
import { MessagesService } from '../messages/messages.service';
import { MediaCleanupService } from '../media/media-cleanup.service';
import { WebPushSubscriptionsService } from '../web-push-subscriptions/web-push-subscriptions.service';
import { RefreshTokensService } from '../auth/refresh-tokens.service';

@Injectable()
export class UsersService {
  private readonly auditLogger = new Logger('Audit');

  constructor(
    @InjectRepository(User)
    private usersRepo: Repository<User>,
    private storageService: LocalStorageService,
    private fcmTokensService: FcmTokensService,
    private webPushSubscriptionsService: WebPushSubscriptionsService,
    private keyBundlesService: KeyBundlesService,
    private dataSource: DataSource,
    private messagesService: MessagesService,
    private mediaCleanup: MediaCleanupService,
    private refreshTokensService: RefreshTokensService,
  ) {}

  async create(username: string, password: string): Promise<User> {
    const existing = await this.findByUsername(username);
    if (existing.length > 0) {
      throw new ConflictException('nickname is already taken');
    }
    // Generate random 4-digit tag (1000-9999); retry on (username, tag) collision
    const hash = await bcrypt.hash(password, 10);
    const maxAttempts = 10;
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      const tag = String(Math.floor(1000 + Math.random() * 9000));
      const existing = await this.findByUsernameAndTag(username, tag);
      if (!existing) {
        const user = this.usersRepo.create({ password: hash, username, tag });
        return this.usersRepo.save(user);
      }
    }
    throw new ConflictException('Could not generate unique tag, please try again');
  }

  async findById(id: number): Promise<User | null> {
    return this.usersRepo.findOne({ where: { id } });
  }

  async findByUsername(username: string): Promise<User[]> {
    return this.usersRepo
      .createQueryBuilder('user')
      .where('LOWER(user.username) = LOWER(:username)', { username })
      .getMany();
  }

  async findByUsernameAndTag(username: string, tag: string): Promise<User | null> {
    return this.usersRepo
      .createQueryBuilder('user')
      .where('LOWER(user.username) = LOWER(:username)', { username })
      .andWhere('user.tag = :tag', { tag })
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

    if (user.profilePicturePublicId && user.profilePicturePublicId !== publicId) {
      await this.storageService.deleteAvatar(user.profilePicturePublicId);
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
    user.passwordChangedAt = new Date();
    await this.usersRepo.save(user);
    await this.refreshTokensService.revokeAllForUser(userId);
    this.auditLogger.log(`resetPassword success userId=${userId}`);
  }

  async deleteAccount(userId: number, password: string): Promise<void> {
    const user = await this.findById(userId);
    if (!user) {
      throw new NotFoundException('User not found');
    }

    const isValidPassword = await bcrypt.compare(password, user.password);
    if (!isValidPassword) {
      throw new UnauthorizedException('Invalid password');
    }

    // External I/O before transaction (non-transactional by nature)
    if (user.profilePicturePublicId) {
      await this.storageService.deleteAvatar(user.profilePicturePublicId);
    }

    // Push tokens/subscriptions and key bundles use their own repos — delete outside transaction
    await this.fcmTokensService.removeByUserId(userId);
    await this.webPushSubscriptionsService.removeByUserId(userId);
    await this.keyBundlesService.deleteByUserId(userId);

    const conversations = await this.usersRepo.manager.find(Conversation, {
      where: [{ userOne: { id: userId } }, { userTwo: { id: userId } }],
    });
    for (const conv of conversations) {
      const urls = await this.messagesService.findMediaUrlsByConversation(
        conv.id,
      );
      await Promise.all(
        urls.map((url) => this.mediaCleanup.deleteMediaFile(url)),
      );
    }

    // All DB operations in a single transaction to prevent partial deletion
    await this.dataSource.transaction(async (manager) => {
      const conversationsInTx = await manager.find(Conversation, {
        where: [{ userOne: { id: userId } }, { userTwo: { id: userId } }],
      });

      for (const conv of conversationsInTx) {
        await manager.delete(Message, { conversation: { id: conv.id } });
        await manager.delete(Conversation, { id: conv.id });
      }

      // Use find-then-remove for friend requests (delete() can't use nested relation conditions)
      const friendRequests = await manager.find(FriendRequest, {
        where: [{ sender: { id: userId } }, { receiver: { id: userId } }],
      });
      if (friendRequests.length > 0) {
        await manager.remove(friendRequests);
      }

      await manager.remove(User, user);
    });

    this.auditLogger.log(`deleteAccount success userId=${userId} username=${user.username}`);
  }
}
