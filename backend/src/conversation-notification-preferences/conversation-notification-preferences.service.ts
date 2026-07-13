import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, IsNull, MoreThan, Repository } from 'typeorm';
import { ConversationNotificationPreference } from './conversation-notification-preference.entity';

export type ConversationMuteDuration = 'off' | '1h' | '8h' | '1w' | 'forever';

export interface ConversationMuteState {
  muted: boolean;
  until: Date | null;
}

@Injectable()
export class ConversationNotificationPreferencesService {
  constructor(
    @InjectRepository(ConversationNotificationPreference)
    private readonly preferences: Repository<ConversationNotificationPreference>,
  ) {}

  async setMute(
    viewerId: number,
    conversationId: number,
    duration: ConversationMuteDuration,
  ): Promise<ConversationMuteState> {
    if (duration === 'off') {
      await this.preferences.delete({ viewerId, conversationId });
      return { muted: false, until: null };
    }

    const mutedUntil = this.mutedUntilFor(duration);
    await this.preferences.upsert(
      { viewerId, conversationId, mutedUntil },
      ['viewerId', 'conversationId'],
    );
    return { muted: true, until: mutedUntil };
  }

  async getMuteStates(
    viewerId: number,
    conversationIds: number[],
    now = new Date(),
  ): Promise<Map<number, ConversationMuteState>> {
    if (conversationIds.length == 0) return new Map();
    const active = await this.preferences.find({
      where: [
        { viewerId, conversationId: In(conversationIds), mutedUntil: IsNull() },
        { viewerId, conversationId: In(conversationIds), mutedUntil: MoreThan(now) },
      ],
    });
    return new Map(active.map((preference) => [
      preference.conversationId,
      { muted: true, until: preference.mutedUntil },
    ]));
  }

  async isMuted(
    viewerId: number,
    conversationId: number,
    now = new Date(),
  ): Promise<boolean> {
    const preference = await this.preferences.findOne({
      where: [
        { viewerId, conversationId, mutedUntil: IsNull() },
        { viewerId, conversationId, mutedUntil: MoreThan(now) },
      ],
    });
    return preference != null;
  }

  private mutedUntilFor(duration: Exclude<ConversationMuteDuration, 'off'>): Date | null {
    if (duration === 'forever') return null;
    const milliseconds = duration === '1h'
      ? 60 * 60 * 1000
      : duration === '8h'
        ? 8 * 60 * 60 * 1000
        : 7 * 24 * 60 * 60 * 1000;
    return new Date(Date.now() + milliseconds);
  }
}
