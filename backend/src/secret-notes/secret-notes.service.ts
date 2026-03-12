// backend/src/secret-notes/secret-notes.service.ts
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { SecretNote } from './secret-note.entity';
import * as crypto from 'crypto';

@Injectable()
export class SecretNotesService {
  constructor(
    @InjectRepository(SecretNote)
    private readonly repo: Repository<SecretNote>,
  ) {}

  async create(ciphertext: string, expiresInSeconds: number, creatorId: number): Promise<{ token: string }> {
    const token = crypto.randomBytes(16).toString('hex'); // 32-char hex
    const expiresAt = new Date(Date.now() + expiresInSeconds * 1000);
    const note = this.repo.create({ token, ciphertext, expiresAt, creatorId });
    await this.repo.save(note);
    return { token };
  }

  async findByToken(token: string): Promise<SecretNote | null> {
    const note = await this.repo.findOne({ where: { token } });
    if (!note) return null;
    if (new Date(note.expiresAt).getTime() < Date.now()) {
      await this.repo.delete({ token });
      return null;
    }
    return note;
  }

  async revealAndDelete(token: string): Promise<{ ciphertext: string } | null> {
    const result = await this.repo.query(
      `DELETE FROM secret_notes WHERE token = $1 AND expires_at > NOW() RETURNING ciphertext`,
      [token],
    );
    if (result.length === 0) return null;
    return { ciphertext: result[0].ciphertext };
  }
}
