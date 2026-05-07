import { HttpStatus } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { Response } from 'express';
import { DataSource } from 'typeorm';
import { HealthController } from './health.controller';

const createMockResponse = (): Response => {
  const res: Partial<Response> = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res as Response;
};

describe('HealthController', () => {
  let controller: HealthController;
  let dataSource: { query: jest.Mock };

  beforeEach(async () => {
    dataSource = { query: jest.fn() };

    const module = await Test.createTestingModule({
      controllers: [HealthController],
      providers: [{ provide: DataSource, useValue: dataSource }],
    }).compile();

    controller = module.get(HealthController);
  });

  it('returns ok when database query succeeds', async () => {
    dataSource.query.mockResolvedValue([1]);
    const res = createMockResponse();

    await controller.check(res);

    expect(dataSource.query).toHaveBeenCalledWith('SELECT 1');
    expect(res.status).toHaveBeenCalledWith(HttpStatus.OK);
    expect(res.json).toHaveBeenCalledWith({ status: 'ok', db: 'ok' });
  });

  it('returns degraded when database query fails', async () => {
    dataSource.query.mockRejectedValue(new Error('db unavailable'));
    const res = createMockResponse();

    await controller.check(res);

    expect(dataSource.query).toHaveBeenCalledWith('SELECT 1');
    expect(res.status).toHaveBeenCalledWith(HttpStatus.SERVICE_UNAVAILABLE);
    expect(res.json).toHaveBeenCalledWith({ status: 'degraded', db: 'error' });
  });
});
