import { ArrayMaxSize, ArrayNotEmpty, IsArray, IsInt } from 'class-validator';

export class ReorderProfilePhotosDto {
  @IsArray()
  @ArrayNotEmpty()
  @ArrayMaxSize(3)
  @IsInt({ each: true })
  orderedIds: number[];
}
