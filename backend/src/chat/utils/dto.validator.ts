import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import { BadRequestException } from '@nestjs/common';

export function validateDto<T extends object>(
  dtoClass: new () => T,
  data: unknown,
): T {
  const instance = plainToInstance(dtoClass, data);
  const errors = validateSync(instance);

  if (errors.length > 0) {
    const errorMessages = errors
      .map((error) => {
        const constraints = error.constraints || {};
        return Object.values(constraints).join(', ');
      })
      .join('; ');

    throw new BadRequestException(`Validation failed: ${errorMessages}`);
  }

  return instance;
}
