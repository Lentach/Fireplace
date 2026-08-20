import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AccountAuthorization } from './account-authorization.entity';
import { Device } from './device.entity';
import { KeyBundle } from './key-bundle.entity';
import { OneTimePreKey } from './one-time-pre-key.entity';
import { IdentityChangeAudit } from './identity-change-audit.entity';
import { IdentityResetRequest } from './identity-reset-request.entity';
import { RecoveryKey } from './recovery-key.entity';
import { DevicesService } from './devices.service';
import { KeyBundlesService } from './key-bundles.service';
import { IdentityResetService } from './identity-reset.service';
import { DeviceListService } from './device-list.service';
import { ProvisioningStagesService } from './provisioning-stages.service';

@Module({
  imports: [
    // Every new entity MUST be here AND in the app.module DataSource list:
    // missing the second throws EntityMetadataNotFoundError at runtime while
    // every mocked unit test stays green (cost Phase 0a a live debug session).
    TypeOrmModule.forFeature([
      AccountAuthorization,
      Device,
      KeyBundle,
      OneTimePreKey,
      IdentityChangeAudit,
      IdentityResetRequest,
      RecoveryKey,
    ]),
  ],
  providers: [
    DevicesService,
    KeyBundlesService,
    IdentityResetService,
    DeviceListService,
    ProvisioningStagesService,
  ],
  exports: [
    DevicesService,
    KeyBundlesService,
    IdentityResetService,
    DeviceListService,
    ProvisioningStagesService,
  ],
})
export class KeyBundlesModule {}
