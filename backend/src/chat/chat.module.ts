import { Module } from '@nestjs/common';
import { ChatGateway } from './chat.gateway';
import { WsThrottlerGuard } from './guards/ws-throttler.guard';
import { ChatMessageService } from './services/chat-message.service';
import { ChatFriendRequestService } from './services/chat-friend-request.service';
import { ChatConversationService } from './services/chat-conversation.service';
import { ChatKeyExchangeService } from './services/chat-key-exchange.service';
import { ChatPresenceService } from './services/chat-presence.service';
import { ChatBlockService } from './services/chat-block.service';
import { ChatValidationModule } from './chat-validation.module';
import { LinkPreviewModule } from './services/link-preview.module';
import { AuthModule } from '../auth/auth.module';
import { UsersModule } from '../users/users.module';
import { ConversationsModule } from '../conversations/conversations.module';
import { MessagesModule } from '../messages/messages.module';
import { FriendsModule } from '../friends/friends.module';
import { BlockedModule } from '../blocked/blocked.module';
import { KeyBundlesModule } from '../key-bundles/key-bundles.module';
import { PushNotificationsModule } from '../push-notifications/push-notifications.module';

@Module({
  imports: [
    AuthModule,
    UsersModule,
    ConversationsModule,
    MessagesModule,
    FriendsModule,
    BlockedModule,
    ChatValidationModule,
    KeyBundlesModule,
    LinkPreviewModule,
    PushNotificationsModule,
  ],
  providers: [
    ChatGateway,
    ChatMessageService,
    ChatFriendRequestService,
    ChatConversationService,
    ChatKeyExchangeService,
    ChatPresenceService,
    ChatBlockService,
    WsThrottlerGuard,
  ],
})
export class ChatModule {}
