import { FriendRequest } from '../../friends/friend-request.entity';
import { UserMapper } from './user.mapper';

export class FriendRequestMapper {
  static toPayload(request: FriendRequest) {
    return {
      id: request.id,
      sender: UserMapper.toPayload(request.sender),
      receiver: UserMapper.toPayload(request.receiver),
      status: request.status,
      createdAt: request.createdAt,
      respondedAt: request.respondedAt,
    };
  }

}
