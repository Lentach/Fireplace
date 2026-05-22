import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { VersionController } from './version.controller';

describe('VersionController', () => {
  let controller: VersionController;

  const createModule = (env: Record<string, string | undefined>) => {
    return Test.createTestingModule({
      controllers: [VersionController],
      providers: [
        {
          provide: ConfigService,
          useValue: {
            get: (key: string) => env[key],
          },
        },
      ],
    }).compile();
  };

  it('returns version metadata from environment', async () => {
    const module = await createModule({
      APP_VERSION: '1.2.3',
      GIT_COMMIT: 'abc1234',
      BUILD_TIME: '2026-05-22T12:00:00Z',
    });
    controller = module.get(VersionController);

    expect(controller.getVersion()).toEqual({
      version: '1.2.3',
      gitCommit: 'abc1234',
      buildTime: '2026-05-22T12:00:00Z',
    });
  });

  it('returns defaults when env vars are unset', async () => {
    const module = await createModule({});
    controller = module.get(VersionController);

    expect(controller.getVersion()).toEqual({
      version: '0.0.1',
      gitCommit: 'unknown',
      buildTime: '',
    });
  });
});
