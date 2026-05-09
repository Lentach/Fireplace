import { Injectable } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { validateDto } from '../utils/dto.validator';
import { PushClientStateDto } from '../dto/push-client-state.dto';
import { TypingDto } from '../dto/typing.dto';
import { RecordingVoiceDto } from '../dto/recording-voice.dto';

@Injectable()
export class ChatPresenceService {
  handleTyping(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ): void {
    const senderId: number = client.data.user?.id;
    if (!senderId) return;
    try {
      const dto = validateDto(TypingDto, data);
      const recipientSocketId = onlineUsers.get(dto.recipientId);
      if (!recipientSocketId) return;
      server.to(recipientSocketId).emit('partnerTyping', {
        senderId,
        conversationId: dto.conversationId,
      });
    } catch {
      return; // invalid payload — silent no-op
    }
  }

  handlePushClientState(client: Socket, data: any): void {
    const userId: number = client.data.user?.id;
    if (!userId) return;
    try {
      const dto = validateDto(PushClientStateDto, data);
      client.data.pushClientState = {
        activeConversationId: dto.activeConversationId ?? null,
        clientVisible: dto.clientVisible,
      };
    } catch {
      return;
    }
  }

  handleRecordingVoice(
    client: Socket,
    data: any,
    server: Server,
    onlineUsers: Map<number, string>,
  ): void {
    const senderId: number = client.data.user?.id;
    if (!senderId) return;
    try {
      const dto = validateDto(RecordingVoiceDto, data);
      const recipientSocketId = onlineUsers.get(dto.recipientId);
      if (!recipientSocketId) return;
      server.to(recipientSocketId).emit('partnerRecordingVoice', {
        senderId,
        conversationId: dto.conversationId,
        isRecording: dto.isRecording,
      });
    } catch {
      return; // invalid payload — silent no-op
    }
  }
}
