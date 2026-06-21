import {
  Controller,
  Post,
  Delete,
  Get,
  Body,
  UseGuards,
  Request,
  UseInterceptors,
  UploadedFile,
  BadRequestException,
  UnauthorizedException,
  Logger,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Throttle } from '@nestjs/throttler';
import { memoryStorage } from 'multer';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { LocalStorageService } from '../media/local-storage.service';
import { UsersService } from './users.service';
import {
  ResetPasswordDto,
  DeleteAccountDto,
  RegisterFcmTokenDto,
  RemoveFcmTokenDto,
  RegisterWebPushSubscriptionDto,
  RemoveWebPushSubscriptionDto,
} from './dto/user.dto';
import { FcmTokensService } from '../fcm-tokens/fcm-tokens.service';
import { WebPushSubscriptionsService } from '../web-push-subscriptions/web-push-subscriptions.service';
import { validateAvatarMagicBytes } from '../media/magic-bytes.validator';

@Controller('users')
export class UsersController {
  private readonly logger = new Logger(UsersController.name);

  constructor(
    private usersService: UsersService,
    private storageService: LocalStorageService,
    private fcmTokensService: FcmTokensService,
    private webPushSubscriptionsService: WebPushSubscriptionsService,
  ) {}

  @Post('profile-picture')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 10, ttl: 3600000 } })
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      fileFilter: (req, file, cb) => {
        if (!file.mimetype.match(/^image\/(jpeg|png)$/)) {
          return cb(
            new BadRequestException('Only JPEG and PNG images are allowed'),
            false,
          );
        }
        cb(null, true);
      },
      limits: {
        fileSize: 5 * 1024 * 1024, // 5MB
      },
    }),
  )
  async uploadProfilePicture(
    @UploadedFile() file: Express.Multer.File,
    @Request() req,
  ) {
    if (!file) {
      throw new BadRequestException('No file uploaded');
    }
    validateAvatarMagicBytes(file.buffer);

    const userId = req.user.id;

    const { secureUrl, publicId } = await this.storageService.uploadAvatar(
      userId,
      file.buffer,
      file.mimetype,
    );

    this.logger.debug(`User ${userId} uploaded profile picture`);

    const user = await this.usersService.updateProfilePicture(
      userId,
      secureUrl,
      publicId,
    );

    return {
      profilePictureUrl: user.profilePictureUrl,
    };
  }

  @Get('me')
  @UseGuards(JwtAuthGuard)
  async getMe(@Request() req) {
    const user = await this.usersService.findById(req.user.id);
    if (!user) throw new UnauthorizedException();
    return {
      id: user.id,
      username: user.username,
      tag: user.tag,
      profilePictureUrl: user.profilePictureUrl ?? null,
    };
  }

  @Post('reset-password')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 10, ttl: 3600000 } })
  async resetPassword(@Body() dto: ResetPasswordDto, @Request() req) {
    const userId = req.user.id;

    this.logger.debug(`User ${userId} requesting password reset`);

    await this.usersService.resetPassword(
      userId,
      dto.oldPassword,
      dto.newPassword,
    );

    return { message: 'Password updated successfully' };
  }

  @Delete('account')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 5, ttl: 3600000 } })
  async deleteAccount(@Body() dto: DeleteAccountDto, @Request() req) {
    const userId = req.user.id;

    this.logger.debug(`User ${userId} requesting account deletion`);

    await this.usersService.deleteAccount(userId, dto.password);

    return { message: 'Account deleted successfully' };
  }

  @Post('fcm-token')
  @UseGuards(JwtAuthGuard)
  async registerFcmToken(@Body() dto: RegisterFcmTokenDto, @Request() req) {
    const userId = req.user.id;
    await this.fcmTokensService.upsert(userId, dto.token, dto.platform);
    return { message: 'FCM token registered' };
  }

  @Delete('fcm-token')
  @UseGuards(JwtAuthGuard)
  async removeFcmToken(@Body() dto: RemoveFcmTokenDto, @Request() req) {
    await this.fcmTokensService.removeByTokenForUser(req.user.id, dto.token);
    return { message: 'FCM token removed' };
  }

  @Post('web-push-subscription')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 30, ttl: 900000 } })
  async registerWebPushSubscription(
    @Body() dto: RegisterWebPushSubscriptionDto,
    @Request() req,
  ) {
    const userId = req.user.id;
    await this.webPushSubscriptionsService.upsert({
      userId,
      endpoint: dto.endpoint,
      p256dh: dto.keys.p256dh,
      auth: dto.keys.auth,
      userAgent: dto.userAgent ?? null,
      expirationTime: dto.expirationTime ?? null,
    });
    return { message: 'Web push subscription registered' };
  }

  @Delete('web-push-subscription')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 30, ttl: 900000 } })
  async removeWebPushSubscription(
    @Body() dto: RemoveWebPushSubscriptionDto,
    @Request() req,
  ) {
    await this.webPushSubscriptionsService.removeByEndpointForUser(
      req.user.id,
      dto.endpoint,
    );
    return { message: 'Web push subscription removed' };
  }
}
