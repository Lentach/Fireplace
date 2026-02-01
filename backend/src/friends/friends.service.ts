import {
  Injectable,
  ConflictException,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { FriendRequest, FriendRequestStatus } from './friend-request.entity';
import { User } from '../users/user.entity';

@Injectable()
export class FriendsService {
  private readonly logger = new Logger(FriendsService.name);

  constructor(
    @InjectRepository(FriendRequest)
    private friendRequestRepository: Repository<FriendRequest>,
  ) {}

  async sendRequest(sender: User, receiver: User): Promise<FriendRequest> {
    if (sender.id === receiver.id) {
      throw new ConflictException('Cannot send friend request to yourself');
    }

    // Check if already friends
    const existingAccepted = await this.friendRequestRepository.findOne({
      where: [
        {
          sender: { id: sender.id },
          receiver: { id: receiver.id },
          status: FriendRequestStatus.ACCEPTED,
        },
        {
          sender: { id: receiver.id },
          receiver: { id: sender.id },
          status: FriendRequestStatus.ACCEPTED,
        },
      ],
    });

    if (existingAccepted) {
      throw new ConflictException('Already friends');
    }

    // Check for duplicate pending request
    const existingPending = await this.friendRequestRepository.findOne({
      where: {
        sender: { id: sender.id },
        receiver: { id: receiver.id },
        status: FriendRequestStatus.PENDING,
      },
    });

    if (existingPending) {
      throw new ConflictException('Friend request already sent');
    }

    // Check for reverse pending request (mutual requests = auto-accept both)
    const reversePending = await this.friendRequestRepository.findOne({
      where: {
        sender: { id: receiver.id },
        receiver: { id: sender.id },
        status: FriendRequestStatus.PENDING,
      },
    });

    // Create the new request
    const newRequest = this.friendRequestRepository.create({
      sender,
      receiver,
      status: FriendRequestStatus.PENDING,
    });

    await this.friendRequestRepository.save(newRequest);

    // Auto-accept both if reverse pending exists
    if (reversePending) {
      await this.friendRequestRepository.update(
        { id: reversePending.id },
        {
          status: FriendRequestStatus.ACCEPTED,
          respondedAt: new Date(),
        },
      );

      await this.friendRequestRepository.update(
        { id: newRequest.id },
        {
          status: FriendRequestStatus.ACCEPTED,
          respondedAt: new Date(),
        },
      );

      const updated = await this.friendRequestRepository.findOne({
        where: { id: newRequest.id },
        relations: ['sender', 'receiver'],
      });
      return updated!;
    }

    return newRequest;
  }

  async acceptRequest(
    requestId: number,
    userId: number,
  ): Promise<FriendRequest> {
    const request = await this.friendRequestRepository.findOne({
      where: { id: requestId },
      relations: ['sender', 'receiver'],
    });

    if (!request) {
      throw new NotFoundException('Friend request not found');
    }

    if (request.receiver.id !== userId) {
      throw new ConflictException('Only receiver can accept this request');
    }

    await this.friendRequestRepository.update(
      { id: requestId },
      {
        status: FriendRequestStatus.ACCEPTED,
        respondedAt: new Date(),
      },
    );

    const updated = await this.friendRequestRepository.findOne({
      where: { id: requestId },
      relations: ['sender', 'receiver'],
    });
    return updated!;
  }

  async rejectRequest(
    requestId: number,
    userId: number,
  ): Promise<FriendRequest> {
    const request = await this.friendRequestRepository.findOne({
      where: { id: requestId },
      relations: ['sender', 'receiver'],
    });

    if (!request) {
      throw new NotFoundException('Friend request not found');
    }

    if (request.receiver.id !== userId) {
      throw new ConflictException('Only receiver can reject this request');
    }

    await this.friendRequestRepository.update(
      { id: requestId },
      {
        status: FriendRequestStatus.REJECTED,
        respondedAt: new Date(),
      },
    );

    const updated = await this.friendRequestRepository.findOne({
      where: { id: requestId },
      relations: ['sender', 'receiver'],
    });
    return updated!;
  }

  async areFriends(userId1: number, userId2: number): Promise<boolean> {
    const friendship = await this.friendRequestRepository.findOne({
      where: [
        {
          sender: { id: userId1 },
          receiver: { id: userId2 },
          status: FriendRequestStatus.ACCEPTED,
        },
        {
          sender: { id: userId2 },
          receiver: { id: userId1 },
          status: FriendRequestStatus.ACCEPTED,
        },
      ],
    });

    return !!friendship;
  }

  async getPendingRequests(userId: number): Promise<FriendRequest[]> {
    return this.friendRequestRepository.find({
      where: {
        receiver: { id: userId },
        status: FriendRequestStatus.PENDING,
      },
      relations: ['sender', 'receiver'],
      order: { createdAt: 'DESC' },
    });
  }

  async getFriends(userId: number): Promise<User[]> {
    const friendRequests = await this.friendRequestRepository.find({
      where: [
        {
          sender: { id: userId },
          status: FriendRequestStatus.ACCEPTED,
        },
        {
          receiver: { id: userId },
          status: FriendRequestStatus.ACCEPTED,
        },
      ],
      relations: ['sender', 'receiver'],
    });

    const friendIds = new Set<number>();
    friendRequests.forEach((fr) => {
      if (fr.sender.id === userId) {
        friendIds.add(fr.receiver.id);
      } else {
        friendIds.add(fr.sender.id);
      }
    });

    return Array.from(friendIds)
      .map((id) => {
        const request = friendRequests.find(
          (fr) =>
            (fr.sender.id === userId && fr.receiver.id === id) ||
            (fr.receiver.id === userId && fr.sender.id === id),
        );
        if (!request) return null;
        return request.sender.id === userId ? request.receiver : request.sender;
      })
      .filter((f) => f !== null);
  }

  async unfriend(userId1: number, userId2: number): Promise<boolean> {
    // TypeORM .delete() does NOT support nested relation conditions (sender: { id })
    // so we must find first, then remove by entity instance (uses primary key)
    const friendships = await this.friendRequestRepository.find({
      where: [
        {
          sender: { id: userId1 },
          receiver: { id: userId2 },
          status: FriendRequestStatus.ACCEPTED,
        },
        {
          sender: { id: userId2 },
          receiver: { id: userId1 },
          status: FriendRequestStatus.ACCEPTED,
        },
      ],
    });

    this.logger.debug(
      `unfriend: found ${friendships.length} ACCEPTED records between users ${userId1} and ${userId2}`,
    );

    if (friendships.length === 0) {
      return false;
    }

    await this.friendRequestRepository.remove(friendships);
    this.logger.debug(`unfriend: removed ${friendships.length} records`);
    return true;
  }

  async getPendingRequestCount(userId: number): Promise<number> {
    return this.friendRequestRepository.countBy({
      receiver: { id: userId },
      status: FriendRequestStatus.PENDING,
    });
  }
}
