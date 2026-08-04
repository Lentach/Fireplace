import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { FriendRequest } from './friend-request.entity';
import { FriendsService } from './friends.service';
import { UsersModule } from '../users/users.module';
import { BlockedModule } from '../blocked/blocked.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([FriendRequest]),
    UsersModule,
    forwardRef(() => BlockedModule),
  ],
  providers: [FriendsService],
  exports: [FriendsService],
})
export class FriendsModule {}
