import { User } from '../../users/user.entity';

export class UserMapper {
  static toPayload(user: User) {
    return {
      id: user.id,
      email: user.email,
      username: user.username,
    };
  }

  static toPayloadArray(users: User[]) {
    return users.map(u => this.toPayload(u));
  }
}
