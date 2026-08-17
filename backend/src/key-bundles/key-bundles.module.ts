import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { KeyBundle } from './key-bundle.entity';
import { OneTimePreKey } from './one-time-pre-key.entity';
import { IdentityChangeAudit } from './identity-change-audit.entity';
import { KeyBundlesService } from './key-bundles.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([KeyBundle, OneTimePreKey, IdentityChangeAudit]),
  ],
  providers: [KeyBundlesService],
  exports: [KeyBundlesService],
})
export class KeyBundlesModule {}
