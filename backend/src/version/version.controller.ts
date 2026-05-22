import { Controller, Get } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface VersionPayload {
  version: string;
  gitCommit: string;
  buildTime: string;
}

@Controller('version')
export class VersionController {
  constructor(private readonly configService: ConfigService) {}

  @Get()
  getVersion(): VersionPayload {
    return {
      version: this.configService.get<string>('APP_VERSION') ?? '0.0.1',
      gitCommit: this.configService.get<string>('GIT_COMMIT') ?? 'unknown',
      buildTime: this.configService.get<string>('BUILD_TIME') ?? '',
    };
  }
}
