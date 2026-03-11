import { Injectable } from '@nestjs/common';
import { FriendsService } from '../../friends/friends.service';
import { BlockedService } from '../../blocked/blocked.service';

export interface ValidateCanMessageResult {
  valid: boolean;
  error?: string;
}

@Injectable()
export class ChatValidationService {
  constructor(
    private readonly friendsService: FriendsService,
    private readonly blockedService: BlockedService,
  ) {}

  async validateCanMessage(
    senderId: number,
    recipientId: number,
  ): Promise<ValidateCanMessageResult> {
    const blocked = await this.blockedService.isBlockedByEither(
      senderId,
      recipientId,
    );
    if (blocked) {
      return { valid: false, error: 'Cannot message this user' };
    }

    const areFriends = await this.friendsService.areFriends(
      senderId,
      recipientId,
    );
    if (!areFriends) {
      return { valid: false, error: 'You can only message friends' };
    }

    return { valid: true };
  }
}
