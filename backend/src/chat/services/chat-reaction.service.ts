import { Injectable, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { MessagesService } from '../../messages/messages.service';
import { BlockedService } from '../../blocked/blocked.service';
import { validateDto } from '../utils/dto.validator';
import { AddReactionDto, RemoveReactionDto } from '../dto/chat.dto';

@Injectable()
export class ChatReactionService {
  private readonly logger = new Logger(ChatReactionService.name);

  constructor(
    private readonly messagesService: MessagesService,
    private readonly blockedService: BlockedService,
  ) {}

  async handleAddReaction(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(AddReactionDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const message = await this.messagesService.findByIdWithConversation(
      data.messageId,
    );
    if (!message) {
      client.emit('error', { message: 'Message not found' });
      return;
    }

    const conv = message.conversation;
    if (conv.userOne.id !== userId && conv.userTwo.id !== userId) {
      client.emit('error', { message: 'Unauthorized' });
      return;
    }

    // Block gate: a block outlives the conversation (handleBlockUser deletes it best-effort
    // only), so re-check here. Fail silently — never leak the block to the sender.
    const otherId =
      conv.userOne.id === userId ? conv.userTwo.id : conv.userOne.id;
    if (await this.blockedService.isBlockedByEither(userId, otherId)) return;

    const updated = await this.messagesService.addOrUpdateReaction(
      data.messageId,
      userId,
      data.emoji,
    );
    if (!updated) return;

    const reactions = updated.reactions ? JSON.parse(updated.reactions) : {};
    const payload = {
      messageId: updated.id,
      conversationId: conv.id,
      reactions,
    };

    client.emit('reactionUpdated', payload);
    const otherUserId =
      conv.userOne.id === userId ? conv.userTwo.id : conv.userOne.id;
    const otherSocketId = onlineUsers.get(otherUserId);
    if (otherSocketId)
      server.to(otherSocketId).emit('reactionUpdated', payload);
  }

  async handleRemoveReaction(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ): Promise<void> {
    const userId: number = client.data.user?.id;
    if (!userId) return;

    try {
      const dto = validateDto(RemoveReactionDto, data);
      data = dto;
    } catch (error) {
      client.emit('error', { message: error.message });
      return;
    }

    const message = await this.messagesService.findByIdWithConversation(
      data.messageId,
    );
    if (!message) {
      client.emit('error', { message: 'Message not found' });
      return;
    }

    const conv = message.conversation;
    if (conv.userOne.id !== userId && conv.userTwo.id !== userId) {
      client.emit('error', { message: 'Unauthorized' });
      return;
    }

    // Block gate: a block outlives the conversation (handleBlockUser deletes it best-effort
    // only), so re-check here. Fail silently — never leak the block to the sender.
    const otherId =
      conv.userOne.id === userId ? conv.userTwo.id : conv.userOne.id;
    if (await this.blockedService.isBlockedByEither(userId, otherId)) return;

    const updated = await this.messagesService.removeReaction(
      data.messageId,
      userId,
      data.emoji,
    );
    if (!updated) return;

    const reactions = updated.reactions ? JSON.parse(updated.reactions) : {};
    const payload = {
      messageId: updated.id,
      conversationId: conv.id,
      reactions,
    };

    client.emit('reactionUpdated', payload);
    const otherUserId =
      conv.userOne.id === userId ? conv.userTwo.id : conv.userOne.id;
    const otherSocketId = onlineUsers.get(otherUserId);
    if (otherSocketId)
      server.to(otherSocketId).emit('reactionUpdated', payload);
  }
}
