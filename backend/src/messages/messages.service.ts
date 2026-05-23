import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Not, Repository } from 'typeorm';
import { Message, MessageDeliveryStatus, MessageType } from './message.entity';
import { User } from '../users/user.entity';
import { Conversation } from '../conversations/conversation.entity';
import { MESSAGE_NOT_EXPIRED_SQL } from './message-expiry.util';

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
      disappearAfterSeconds?: number | null;
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
      expiresAt: options?.expiresAt ?? null,
      disappearAfterSeconds: options?.disappearAfterSeconds ?? null,
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
    qb.andWhere(MESSAGE_NOT_EXPIRED_SQL, { now: new Date() });
    qb.andWhere(
      `(m."hiddenByUserIds" IS NULL OR m."hiddenByUserIds" = '' OR ` +
        `(',' || COALESCE(m."hiddenByUserIds", '') || ',' NOT LIKE '%,' || :uid::text || ',%'))`,
      { uid: recipientUserId },
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
    const ids = conversationIds.map((id) => Number(id)).filter((id) => !Number.isNaN(id));
    if (ids.length === 0) return new Map();
    const rows = await this.msgRepo
      .createQueryBuilder('m')
      .innerJoin('m.sender', 's')
      .select('m.conversation_id', 'conversationId')
      .addSelect('COUNT(*)::int', 'count')
      .where('m.conversation_id IN (:...ids)', { ids })
      .andWhere('s.id != :userId', { userId: recipientUserId })
      .andWhere('m."deliveryStatus" != :status', {
        status: MessageDeliveryStatus.READ,
      })
      .andWhere(MESSAGE_NOT_EXPIRED_SQL, { now: new Date() })
      .andWhere(
        `(m."hiddenByUserIds" IS NULL OR m."hiddenByUserIds" = '' OR ` +
          `(',' || COALESCE(m."hiddenByUserIds", '') || ',' NOT LIKE '%,' || :uid::text || ',%'))`,
        { uid: recipientUserId },
      )
      .groupBy('m.conversation_id')
      .getRawMany();
    const map = new Map<number, number>();
    for (const r of rows) {
      map.set(Number(r.conversationId), Number(r.count));
    }
    for (const id of ids) {
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
    const ids = conversationIds.map((id) => Number(id)).filter((id) => !Number.isNaN(id));
    if (ids.length === 0) return new Map();
    let hiddenClause = '';
    const queryParams: unknown[] = [ids];
    if (hiddenByUserId != null) {
      queryParams.push(hiddenByUserId);
      const uidParamIdx = queryParams.length;
      hiddenClause =
        ` AND ("hiddenByUserIds" IS NULL OR "hiddenByUserIds" = '' OR ` +
        `(',' || COALESCE("hiddenByUserIds", '') || ',' NOT LIKE '%,' || $${uidParamIdx}::text || ',%'))`;
    }
    const rawRows = await this.msgRepo.query(
      `SELECT id, conversation_id as "conversationId" FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY conversation_id ORDER BY "createdAt" DESC) as rn
        FROM messages
        WHERE conversation_id = ANY($1::int[])${hiddenClause}
      ) sub WHERE rn = 1`,
      queryParams,
    );
    const msgIds = rawRows.map((r: { id: unknown }) => Number(r.id)).filter((id) => !Number.isNaN(id));
    const convIdByMsgId = new Map<number, number>();
    for (const r of rawRows) {
      const mid = Number((r as { id: unknown }).id);
      const cid = Number((r as { conversationId: unknown }).conversationId);
      if (!Number.isNaN(mid) && !Number.isNaN(cid)) convIdByMsgId.set(mid, cid);
    }
    if (msgIds.length === 0) {
      const map = new Map<number, Message | null>();
      for (const id of conversationIds) map.set(Number(id), null);
      return map;
    }
    const messages = await this.msgRepo.find({
      where: { id: In(msgIds) },
      relations: ['sender'],
    });
    const byConvId = new Map<number, Message>();
    for (const m of messages) {
      const convId = convIdByMsgId.get(m.id);
      if (convId != null) byConvId.set(convId, m);
    }
    const map = new Map<number, Message | null>();
    for (const id of conversationIds) {
      const numId = Number(id);
      map.set(numId, byConvId.get(numId) ?? null);
    }
    return map;
  }

  /**
   * Batch fetch pinned message rows for conversation list snapshots.
   * Returns Map<conversationId, Message | null>.
   */
  async getPinnedMessagesBatch(
    entries: Array<{ conversationId: number; pinnedMessageId: number | null }>,
    hiddenByUserId?: number,
  ): Promise<Map<number, Message | null>> {
    const map = new Map<number, Message | null>();
    const pinnedIds: number[] = [];
    const convIdByMsgId = new Map<number, number>();
    for (const entry of entries) {
      const convId = Number(entry.conversationId);
      map.set(convId, null);
      const pinnedId = entry.pinnedMessageId;
      if (pinnedId != null && !Number.isNaN(Number(pinnedId))) {
        const msgId = Number(pinnedId);
        pinnedIds.push(msgId);
        convIdByMsgId.set(msgId, convId);
      }
    }
    if (pinnedIds.length === 0) return map;

    const messages = await this.msgRepo.find({
      where: { id: In(pinnedIds) },
      relations: ['sender', 'conversation'],
    });

    for (const m of messages) {
      const convId = convIdByMsgId.get(m.id);
      if (convId == null) continue;
      if (hiddenByUserId != null) {
        const hidden = m.hiddenByUserIds ?? '';
        if (hidden.length > 0) {
          const padded = `,${hidden},`;
          if (padded.includes(`,${hiddenByUserId},`)) {
            map.set(convId, null);
            continue;
          }
        }
      }
      map.set(convId, m);
    }
    return map;
  }

  /** Mark all messages in the conversation that were sent BY senderId (to the other participant) as READ. Returns only the messages that were actually changed (were not already READ). */
  async markConversationAsReadFromSender(
    conversationId: number,
    senderId: number,
  ): Promise<Message[]> {
    // Fetch messages that will actually be changed (not yet READ) before the update
    const toUpdate = await this.msgRepo.find({
      where: {
        conversation: { id: conversationId },
        sender: { id: senderId },
        deliveryStatus: Not(MessageDeliveryStatus.READ),
      },
      relations: ['sender'],
    });

    if (toUpdate.length === 0) return [];

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

    const readMessages = toUpdate.map(
      (m) => ({ ...m, deliveryStatus: MessageDeliveryStatus.READ }) as Message,
    );

    const now = new Date();
    const expiryUpdates: Message[] = [];
    for (const msg of readMessages) {
      if (
        msg.disappearAfterSeconds != null &&
        msg.expiresAt == null
      ) {
        msg.expiresAt = new Date(
          now.getTime() + msg.disappearAfterSeconds * 1000,
        );
        expiryUpdates.push(msg);
      }
    }
    if (expiryUpdates.length > 0) {
      await this.msgRepo.save(expiryUpdates);
    }

    return readMessages;
  }

  /** Non-null media URLs in a conversation (for disk cleanup before row delete). */
  async findMediaUrlsByConversation(conversationId: number): Promise<string[]> {
    const rows = await this.msgRepo
      .createQueryBuilder('m')
      .select('m.mediaUrl', 'mediaUrl')
      .where('m.conversation_id = :id', { id: conversationId })
      .andWhere('m.mediaUrl IS NOT NULL')
      .getRawMany();
    return rows
      .map((r: { mediaUrl: string | null }) => r.mediaUrl)
      .filter((u): u is string => !!u);
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
