import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { KeyBundle } from './key-bundle.entity';
import { OneTimePreKey } from './one-time-pre-key.entity';
import { IdentityChangeAudit } from './identity-change-audit.entity';
import { IdentityResetRequest } from './identity-reset-request.entity';
import { RecoveryKey } from './recovery-key.entity';
import { KeyBundlesService } from './key-bundles.service';
import { IdentityResetService } from './identity-reset.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      KeyBundle,
      OneTimePreKey,
      IdentityChangeAudit,
      IdentityResetRequest,
      RecoveryKey,
    ]),
  ],
  providers: [KeyBundlesService, IdentityResetService],
  exports: [KeyBundlesService, IdentityResetService],
})
export class KeyBundlesModule {}
