import { Controller, Get, HttpStatus, Res } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import type { Response } from 'express';
import { DataSource } from 'typeorm';

@Controller('health')
export class HealthController {
  constructor(@InjectDataSource() private readonly dataSource: DataSource) {}

  @Get()
  async check(@Res() res: Response) {
    try {
      await this.dataSource.query('SELECT 1');
      return res.status(HttpStatus.OK).json({ status: 'ok', db: 'ok' });
    } catch {
      return res
        .status(HttpStatus.SERVICE_UNAVAILABLE)
        .json({ status: 'degraded', db: 'error' });
    }
  }
}
