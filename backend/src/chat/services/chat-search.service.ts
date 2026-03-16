import { Injectable, Logger } from '@nestjs/common';
import { Socket } from 'socket.io';
import { UsersService } from '../../users/users.service';
import { FriendsService } from '../../friends/friends.service';
import { validateDto } from '../utils/dto.validator';
import { SearchUsersDto } from '../dto/chat.dto';
import { UserMapper } from '../mappers/user.mapper';

@Injectable()
export class ChatSearchService {
  private readonly logger = new Logger(ChatSearchService.name);

  constructor(
    private readonly usersService: UsersService,
    private readonly friendsService: FriendsService,
  ) {}

  async handleSearchUsers(client: Socket, data: any) {
    const currentUserId = client.data.user?.id;
    if (!currentUserId) return;

    try {
      const dto = validateDto(SearchUsersDto, data);
      const [username, tag] = dto.handle.split('#');
      const user = await this.usersService.findByUsernameAndTag(username, tag);
      if (!user || user.id === currentUserId) {
        client.emit('searchUsersResult', []);
        return;
      }
      const friendIds = new Set(
        (await this.friendsService.getFriends(currentUserId)).map((u) => u.id),
      );
      if (friendIds.has(user.id)) {
        client.emit('searchUsersResult', []);
        return;
      }
      client.emit('searchUsersResult', [UserMapper.toPayload(user)]);
    } catch (error) {
      client.emit('error', { message: error?.message || 'Search failed' });
    }
  }
}
