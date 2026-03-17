import { Injectable } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { BlockedService } from '../../blocked/blocked.service';
import { UserMapper } from '../mappers/user.mapper';
import { validateDto } from '../utils/dto.validator';
import { BlockUserDto } from '../dto/chat.dto';

@Injectable()
export class ChatBlockService {
  constructor(private readonly blockedService: BlockedService) {}

  async handleBlockUser(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;
    try {
      const dto = validateDto(BlockUserDto, data);
      if (dto.userId === userId) {
        client.emit('error', { message: 'Cannot block yourself' });
        return;
      }
      await this.blockedService.block(userId, dto.userId);
      const blocked = await this.blockedService.getBlockedUsers(userId);
      client.emit('blockedList', blocked.map((u) => UserMapper.toPayload(u)));
      // Notify the blocked user so they can remove blocker from conversations/contacts
      const blockedUserSocketId = onlineUsers.get(dto.userId);
      if (blockedUserSocketId) {
        server.to(blockedUserSocketId).emit('youWereBlocked', { userId });
      }
    } catch (error) {
      client.emit('error', { message: error?.message || 'Failed to block user' });
    }
  }

  async handleUnblockUser(
    client: Socket,
    data: any,
  ): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;
    try {
      const dto = validateDto(BlockUserDto, data);
      await this.blockedService.unblock(userId, dto.userId);
      const blocked = await this.blockedService.getBlockedUsers(userId);
      client.emit('blockedList', blocked.map((u) => UserMapper.toPayload(u)));
    } catch (error) {
      client.emit('error', { message: error?.message || 'Failed to unblock user' });
    }
  }

  async handleGetBlockedList(client: Socket): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;
    const blocked = await this.blockedService.getBlockedUsers(userId);
    client.emit('blockedList', blocked.map((u) => UserMapper.toPayload(u)));
  }
}
