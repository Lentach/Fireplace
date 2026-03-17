import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { BlockedUser } from './blocked-user.entity';
import { User } from '../users/user.entity';
import { FriendsService } from '../friends/friends.service';
import { ConversationsService } from '../conversations/conversations.service';

@Injectable()
export class BlockedService {
  private readonly logger = new Logger(BlockedService.name);

  constructor(
    @InjectRepository(BlockedUser)
    private readonly blockedRepo: Repository<BlockedUser>,
    private readonly friendsService: FriendsService,
    private readonly conversationsService: ConversationsService,
  ) {}

  async block(blockerId: number, blockedId: number): Promise<BlockedUser> {
    if (blockerId === blockedId) {
      throw new Error('Cannot block yourself');
    }
    let existing = await this.blockedRepo.findOne({
      where: { blocker: { id: blockerId }, blocked: { id: blockedId } },
    });
    if (existing) {
      return existing;
    }
    const record = this.blockedRepo.create({
      blocker: { id: blockerId } as User,
      blocked: { id: blockedId } as User,
    });
    await this.blockedRepo.save(record);
    await this.friendsService.unfriend(blockerId, blockedId);
    // Delete the conversation and messages so that after unblock + re-add they get a fresh chat.
    try {
      const conv = await this.conversationsService.findByUsers(
        blockerId,
        blockedId,
      );
      if (conv) {
        await this.conversationsService.delete(conv.id);
        this.logger.debug(
          `Block: deleted conversation id=${conv.id} between ${blockerId} and ${blockedId}`,
        );
      }
    } catch (err) {
      this.logger.warn(
        `Block: failed to delete conversation (non-critical): ${(err as Error)?.message}`,
      );
    }
    this.logger.debug(`User ${blockerId} blocked user ${blockedId}`);
    return record;
  }

  async unblock(blockerId: number, blockedId: number): Promise<boolean> {
    const result = await this.blockedRepo.delete({
      blocker: { id: blockerId },
      blocked: { id: blockedId },
    });
    if (result.affected && result.affected > 0) {
      this.logger.debug(`User ${blockerId} unblocked user ${blockedId}`);
      return true;
    }
    return false;
  }

  async getBlockedUserIds(blockerId: number): Promise<number[]> {
    const rows = await this.blockedRepo.find({
      where: { blocker: { id: blockerId } },
      relations: ['blocked'],
    });
    return rows.map((r) => r.blocked.id);
  }

  /** User IDs who have blocked this user (so we can hide them from their lists). */
  async getBlockedByUserIds(blockedId: number): Promise<number[]> {
    const rows = await this.blockedRepo.find({
      where: { blocked: { id: blockedId } },
      relations: ['blocker'],
    });
    return rows.map((r) => r.blocker.id);
  }

  async getBlockedUsers(blockerId: number): Promise<User[]> {
    const rows = await this.blockedRepo.find({
      where: { blocker: { id: blockerId } },
      relations: ['blocked'],
    });
    return rows.map((r) => r.blocked);
  }

  /** True if blockerId has blocked blockedId */
  async isBlocked(blockerId: number, blockedId: number): Promise<boolean> {
    const one = await this.blockedRepo.findOne({
      where: { blocker: { id: blockerId }, blocked: { id: blockedId } },
    });
    return !!one;
  }

  /** True if either user has blocked the other. Single query instead of two sequential round-trips. */
  async isBlockedByEither(userId1: number, userId2: number): Promise<boolean> {
    const count = await this.blockedRepo
      .createQueryBuilder('bu')
      .where(
        '(bu.blocker_id = :a AND bu.blocked_id = :b) OR (bu.blocker_id = :b AND bu.blocked_id = :a)',
        { a: userId1, b: userId2 },
      )
      .getCount();
    return count > 0;
  }
}
