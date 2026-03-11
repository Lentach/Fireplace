import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Message, MessageDeliveryStatus, MessageType } from './message.entity';
import { User } from '../users/user.entity';
import { Conversation } from '../conversations/conversation.entity';

@Injectable()
export class MessagesService {
  constructor(
    @InjectRepository(Message)
    private msgRepo: Repository<Message>,
  ) {}

  async create(
    content: string,
    sender: User,
    conversation: Conversation,
    options?: {
      deliveryStatus?: MessageDeliveryStatus;
      expiresAt?: Date | null;
      messageType?: MessageType;
      mediaUrl?: string | null;
      mediaDuration?: number | null;
      replyToMessageId?: number | null;
      encryptedContent?: string | null;
    },
  ): Promise<Message> {
    let replyTo: Message | null = null;
    if (options?.replyToMessageId != null) {
      const replyToMsg = await this.msgRepo.findOne({
        where: { id: options.replyToMessageId, conversation: { id: conversation.id } },
        relations: ['sender'],
      });
      if (replyToMsg) {
        replyTo = replyToMsg;
      }
    }

    const msg = this.msgRepo.create({
      content,
      sender,
      conversation,
      deliveryStatus: options?.deliveryStatus || MessageDeliveryStatus.SENT,
      expiresAt: options?.expiresAt || null,
      messageType: options?.messageType || MessageType.TEXT,
      mediaUrl: options?.mediaUrl || null,
      mediaDuration: options?.mediaDuration || null,
      encryptedContent: options?.encryptedContent || null,
      replyTo,
    });
    const saved = await this.msgRepo.save(msg);
    if (replyTo) {
      saved.replyTo = replyTo;
      return saved;
    }
    return saved;
  }

  /** Parse hiddenByUserIds string "1,2,3" to number[] */
  static parseHiddenIds(s: string | null | undefined): number[] {
    if (!s || typeof s !== 'string') return [];
    return s
      .split(',')
      .map((x) => parseInt(x.trim(), 10))
      .filter((n) => !isNaN(n));
  }

  // Get messages from a conversation with pagination support.
  // Fetches the N most recent messages (DESC), returns them oldest-first (ASC) for display.
  // offset=0: newest messages; offset=50: next 50 older messages.
  // Pass hiddenByUserId to filter out messages that user has "deleted for me".
  async findByConversation(
    conversationId: number,
    limit: number = 50,
    offset: number = 0,
    hiddenByUserId?: number,
  ): Promise<Message[]> {
    if (hiddenByUserId == null) {
      // No hidden messages: efficient DB-level pagination
      const messages = await this.msgRepo.find({
        where: { conversation: { id: conversationId } },
        relations: ['sender', 'replyTo', 'replyTo.sender'],
        order: { createdAt: 'DESC' },
        take: limit,
        skip: offset,
      });
      return messages.reverse();
    }

    // With hidden messages: fetch extra rows to account for filtered items.
    // No artificial 500-cap — use a generous multiple so deep offsets work.
    const fetchLimit = limit * 3 + offset + 50;
    const messages = await this.msgRepo.find({
      where: { conversation: { id: conversationId } },
      relations: ['sender', 'replyTo', 'replyTo.sender'],
      order: { createdAt: 'DESC' },
      take: fetchLimit,
      skip: 0,
    });

    const filtered = messages.filter(
      (m) => !MessagesService.parseHiddenIds(m.hiddenByUserIds).includes(hiddenByUserId),
    );
    return filtered.slice(offset, offset + limit).reverse();
  }

  /** Find message by ID with conversation and sender loaded (for delete flow). */
  async findByIdWithConversation(messageId: number): Promise<Message | null> {
    const message = await this.msgRepo.findOne({
      where: { id: messageId },
      relations: ['sender', 'conversation', 'conversation.userOne', 'conversation.userTwo'],
    });
    return message || null;
  }

  // Get the last (most recent) message from a conversation.
  // Pass hiddenByUserId to exclude messages that user has "deleted for me".
  async getLastMessage(
    conversationId: number,
    hiddenByUserId?: number,
  ): Promise<Message | null> {
    const messages = await this.msgRepo.find({
      where: { conversation: { id: conversationId } },
      relations: ['sender'],
      order: { createdAt: 'DESC' },
      take: hiddenByUserId != null ? 50 : 1,
    });
    if (messages.length === 0) return null;
    if (hiddenByUserId == null) return messages[0];
    const visible = messages.find(
      (m) => !MessagesService.parseHiddenIds(m.hiddenByUserIds).includes(hiddenByUserId),
    );
    return visible || null;
  }

  /** Status order: never downgrade (e.g. READ must not become DELIVERED when events are processed out of order). */
  private static readonly DELIVERY_STATUS_ORDER: Record<MessageDeliveryStatus, number> = {
    [MessageDeliveryStatus.SENDING]: 0,
    [MessageDeliveryStatus.SENT]: 1,
    [MessageDeliveryStatus.DELIVERED]: 2,
    [MessageDeliveryStatus.READ]: 3,
  };

  async updateDeliveryStatus(
    messageId: number,
    status: MessageDeliveryStatus,
  ): Promise<Message | null> {
    const message = await this.msgRepo.findOne({
      where: { id: messageId },
      relations: ['sender', 'conversation'],
    });

    if (!message) {
      return null;
    }

    const currentOrder = MessagesService.DELIVERY_STATUS_ORDER[message.deliveryStatus];
    const newOrder = MessagesService.DELIVERY_STATUS_ORDER[status];
    if (newOrder <= currentOrder) {
      return message;
    }

    message.deliveryStatus = status;
    return this.msgRepo.save(message);
  }

  /**
   * Count unread messages for a recipient in a conversation.
   * Unread = messages sent by the other participant, not yet READ, not expired.
   * Excludes messages hidden by recipientUserId (delete for me).
   */
  async countUnreadForRecipient(
    conversationId: number,
    recipientUserId: number,
  ): Promise<number> {
    const qb = this.msgRepo
      .createQueryBuilder('m')
      .innerJoin('m.sender', 's')
      .where('m.conversation_id = :convId', { convId: conversationId })
      .andWhere('s.id != :userId', { userId: recipientUserId })
      .andWhere('m."deliveryStatus" != :status', {
        status: MessageDeliveryStatus.READ,
      });
    qb.andWhere(
      '(m."expiresAt" IS NULL OR m."expiresAt" > CURRENT_TIMESTAMP)',
    );
    qb.andWhere(
      `(m."hiddenByUserIds" IS NULL OR m."hiddenByUserIds" = '' OR ` +
        `(',' || COALESCE(m."hiddenByUserIds", '') || ',' NOT LIKE :hiddenPattern))`,
      { hiddenPattern: `%,${recipientUserId},%` },
    );
    return qb.getCount();
  }

  /**
   * Batch count unread for multiple conversations (I3: avoids N+1).
   * Returns Map<conversationId, unreadCount>.
   */
  async countUnreadForRecipientBatch(
    conversationIds: number[],
    recipientUserId: number,
  ): Promise<Map<number, number>> {
    if (conversationIds.length === 0) return new Map();
    const hiddenPattern = `%,${recipientUserId},%`;
    const rows = await this.msgRepo
      .createQueryBuilder('m')
      .innerJoin('m.sender', 's')
      .select('m.conversation_id', 'conversationId')
      .addSelect('COUNT(*)::int', 'count')
      .where('m.conversation_id IN (:...ids)', { ids: conversationIds })
      .andWhere('s.id != :userId', { userId: recipientUserId })
      .andWhere('m."deliveryStatus" != :status', {
        status: MessageDeliveryStatus.READ,
      })
      .andWhere(
        '(m."expiresAt" IS NULL OR m."expiresAt" > CURRENT_TIMESTAMP)',
      )
      .andWhere(
        `(m."hiddenByUserIds" IS NULL OR m."hiddenByUserIds" = '' OR ` +
          `(',' || COALESCE(m."hiddenByUserIds", '') || ',' NOT LIKE :hiddenPattern))`,
        { hiddenPattern },
      )
      .groupBy('m.conversation_id')
      .getRawMany();
    const map = new Map<number, number>();
    for (const r of rows) {
      map.set(Number(r.conversationId), Number(r.count));
    }
    for (const id of conversationIds) {
      if (!map.has(id)) map.set(id, 0);
    }
    return map;
  }

  /**
   * Batch get last message per conversation (I3: avoids N+1).
   * Uses PostgreSQL DISTINCT ON. Returns Map<conversationId, Message | null>.
   */
  async getLastMessagesBatch(
    conversationIds: number[],
    hiddenByUserId?: number,
  ): Promise<Map<number, Message | null>> {
    if (conversationIds.length === 0) return new Map();
    let hiddenClause = '';
    if (hiddenByUserId != null) {
      hiddenClause =
        ` AND ("hiddenByUserIds" IS NULL OR "hiddenByUserIds" = '' OR ` +
        `(',' || COALESCE("hiddenByUserIds", '') || ',' NOT LIKE '%,${hiddenByUserId},%'))`;
    }
    const rawRows = await this.msgRepo.query(
      `SELECT id, conversation_id as "conversationId" FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY conversation_id ORDER BY "createdAt" DESC) as rn
        FROM messages
        WHERE conversation_id = ANY($1::int[])${hiddenClause}
      ) sub WHERE rn = 1`,
      [conversationIds],
    );
    const msgIds = rawRows.map((r: { id: number }) => r.id);
    const convIdByMsgId = new Map<number, number>();
    for (const r of rawRows) {
      convIdByMsgId.set(r.id, r.conversationId);
    }
    if (msgIds.length === 0) {
      const map = new Map<number, Message | null>();
      for (const id of conversationIds) map.set(id, null);
      return map;
    }
    const messages = await this.msgRepo.find({
      where: { id: msgIds as any },
      relations: ['sender'],
    });
    const byConvId = new Map<number, Message>();
    for (const m of messages) {
      const convId = convIdByMsgId.get(m.id);
      if (convId != null) byConvId.set(convId, m);
    }
    const map = new Map<number, Message | null>();
    for (const id of conversationIds) {
      map.set(id, byConvId.get(id) ?? null);
    }
    return map;
  }

  /** Mark all messages in the conversation that were sent BY senderId (to the other participant) as READ. Returns updated messages with sender. */
  async markConversationAsReadFromSender(
    conversationId: number,
    senderId: number,
  ): Promise<Message[]> {
    // Batch update — single query instead of N individual saves
    await this.msgRepo
      .createQueryBuilder()
      .update(Message)
      .set({ deliveryStatus: MessageDeliveryStatus.READ })
      .where(
        'conversation_id = :convId AND sender_id = :senderId AND "deliveryStatus" != :status',
        {
          convId: conversationId,
          senderId,
          status: MessageDeliveryStatus.READ,
        },
      )
      .execute();

    // Return all sender messages in conversation for event emission
    return this.msgRepo.find({
      where: {
        conversation: { id: conversationId },
        sender: { id: senderId },
      },
      relations: ['sender'],
    });
  }

  /**
   * Delete all messages in a conversation.
   * Used when clearing chat history.
   */
  async deleteAllByConversation(conversationId: number): Promise<void> {
    await this.msgRepo.delete({ conversation: { id: conversationId } });
  }

  /**
   * "Delete for me" — add userId to hiddenByUserIds so message is hidden from that user.
   */
  async hideMessageForUser(messageId: number, userId: number): Promise<boolean> {
    const message = await this.msgRepo.findOne({
      where: { id: messageId },
      relations: ['conversation'],
    });
    if (!message) return false;

    const ids = MessagesService.parseHiddenIds(message.hiddenByUserIds);
    if (ids.includes(userId)) return true; // Already hidden
    ids.push(userId);
    message.hiddenByUserIds = ids.join(',');
    await this.msgRepo.save(message);
    return true;
  }

  async addOrUpdateReaction(
    messageId: number,
    userId: number,
    emoji: string,
  ): Promise<Message | null> {
    const message = await this.msgRepo.findOne({
      where: { id: messageId },
      relations: ['sender', 'conversation'],
    });
    if (!message) return null;

    const reactions: Record<string, number[]> = message.reactions
      ? JSON.parse(message.reactions)
      : {};

    // Remove user's previous emoji (max 1 per user)
    for (const key of Object.keys(reactions)) {
      reactions[key] = reactions[key].filter((id) => id !== userId);
      if (reactions[key].length === 0) delete reactions[key];
    }

    // Add new emoji
    if (!reactions[emoji]) reactions[emoji] = [];
    reactions[emoji].push(userId);

    message.reactions = JSON.stringify(reactions);
    return this.msgRepo.save(message);
  }

  async removeReaction(
    messageId: number,
    userId: number,
    emoji: string,
  ): Promise<Message | null> {
    const message = await this.msgRepo.findOne({
      where: { id: messageId },
      relations: ['sender', 'conversation'],
    });
    if (!message) return null;

    const reactions: Record<string, number[]> = message.reactions
      ? JSON.parse(message.reactions)
      : {};

    if (reactions[emoji]) {
      reactions[emoji] = reactions[emoji].filter((id) => id !== userId);
      if (reactions[emoji].length === 0) delete reactions[emoji];
    }

    message.reactions = JSON.stringify(reactions);
    return this.msgRepo.save(message);
  }

  async updateLinkPreview(
    messageId: number,
    url: string,
    title: string | null,
    imageUrl: string | null,
  ): Promise<Message | null> {
    const message = await this.msgRepo.findOne({ where: { id: messageId } });
    if (!message) return null;
    message.linkPreviewUrl = url;
    message.linkPreviewTitle = title;
    message.linkPreviewImageUrl = imageUrl;
    return this.msgRepo.save(message);
  }

  /**
   * "Delete for everyone" — hard delete the message. Only sender can call this.
   */
  async deleteById(messageId: number, requesterId: number): Promise<Message | null> {
    const message = await this.msgRepo.findOne({
      where: { id: messageId },
      relations: ['sender', 'conversation'],
    });
    if (!message) return null;
    if (message.sender.id !== requesterId) return null;
    await this.msgRepo.remove(message);
    return message;
  }
}
