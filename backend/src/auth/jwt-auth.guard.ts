import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

// Guard do ochrony endpointów — wystarczy dodać @UseGuards(JwtAuthGuard)
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
