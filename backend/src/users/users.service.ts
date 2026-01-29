import { Injectable, ConflictException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { User } from './user.entity';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User)
    private usersRepo: Repository<User>,
  ) {}

  async create(email: string, password: string): Promise<User> {
    // Sprawdzamy czy email jest już zajęty
    const existing = await this.usersRepo.findOne({ where: { email } });
    if (existing) {
      throw new ConflictException('Email already in use');
    }

    // 10 rund bcrypt — dobry balans bezpieczeństwo/wydajność
    const hash = await bcrypt.hash(password, 10);

    const user = this.usersRepo.create({ email, password: hash });
    return this.usersRepo.save(user);
  }

  async findByEmail(email: string): Promise<User | null> {
    return this.usersRepo
      .createQueryBuilder('user')
      .where('LOWER(user.email) = LOWER(:email)', { email })
      .getOne();
  }

  async findById(id: number): Promise<User | null> {
    return this.usersRepo.findOne({ where: { id } });
  }
}
