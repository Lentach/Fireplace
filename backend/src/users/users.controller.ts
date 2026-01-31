import {
  Controller,
  Post,
  Delete,
  Patch,
  Body,
  UseGuards,
  Request,
  UseInterceptors,
  UploadedFile,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Throttle } from '@nestjs/throttler';
import { diskStorage } from 'multer';
import { extname } from 'path';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { UsersService } from './users.service';
import {
  ResetPasswordDto,
  DeleteAccountDto,
  UpdateActiveStatusDto,
} from './dto/user.dto';

@Controller('users')
export class UsersController {
  private readonly logger = new Logger(UsersController.name);

  constructor(private usersService: UsersService) {}

  @Post('profile-picture')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 10, ttl: 3600000 } })
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: './uploads/profiles',
        filename: (req, file, cb) => {
          const userId = req.user?.['id'] || 'unknown';
          const timestamp = Date.now();
          const ext = extname(file.originalname);
          cb(null, `user-${userId}-${timestamp}${ext}`);
        },
      }),
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

    const userId = req.user.id;
    const relativePath = `/uploads/profiles/${file.filename}`;

    this.logger.debug(
      `User ${userId} uploaded profile picture: ${relativePath}`,
    );

    const user = await this.usersService.updateProfilePicture(
      userId,
      relativePath,
    );

    return {
      profilePictureUrl: user.profilePictureUrl,
    };
  }

  @Post('reset-password')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 3, ttl: 3600000 } })
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
  @Throttle({ default: { limit: 1, ttl: 3600000 } })
  async deleteAccount(@Body() dto: DeleteAccountDto, @Request() req) {
    const userId = req.user.id;

    this.logger.debug(`User ${userId} requesting account deletion`);

    await this.usersService.deleteAccount(userId, dto.password);

    return { message: 'Account deleted successfully' };
  }

  @Patch('active-status')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: 20, ttl: 3600000 } })
  async updateActiveStatus(@Body() dto: UpdateActiveStatusDto, @Request() req) {
    const userId = req.user.id;

    this.logger.debug(
      `User ${userId} updating active status to ${dto.activeStatus}`,
    );

    const user = await this.usersService.updateActiveStatus(
      userId,
      dto.activeStatus,
    );

    return {
      activeStatus: user.activeStatus,
    };
  }
}
