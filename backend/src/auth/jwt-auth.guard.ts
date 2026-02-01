import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

// Guard for protecting endpoints — add @UseGuards(JwtAuthGuard)
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
