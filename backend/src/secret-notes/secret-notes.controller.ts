// backend/src/secret-notes/secret-notes.controller.ts
import {
  Controller, Post, Get, Body, Param, Req, Res, UseGuards,
} from '@nestjs/common';
import { IsString, IsNotEmpty, IsInt, MaxLength } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { SecretNotesService } from './secret-notes.service';
import { Response } from 'express';

class CreateNoteDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(65536)
  ciphertext: string;

  @IsInt()
  expiresIn: number; // seconds: 7200 | 21600 | 43200
}

@Controller()
export class SecretNotesController {
  constructor(private readonly service: SecretNotesService) {}

  @UseGuards(JwtAuthGuard)
  @Post('notes')
  async createNote(@Body() dto: CreateNoteDto, @Req() req: any) {
    const validTtls = [7200, 21600, 43200];
    const expiresIn = validTtls.includes(dto.expiresIn) ? dto.expiresIn : 21600;
    return this.service.create(dto.ciphertext, expiresIn, req.user.userId);
  }

  @Get('note/:token')
  async getNotePage(@Param('token') token: string, @Res() res: Response) {
    const note = await this.service.findByToken(token);
    if (!note) {
      res.send(this.destroyedPage());
      return;
    }
    const remainingMs = new Date(note.expiresAt).getTime() - Date.now();
    const remainingLabel = this.formatRemaining(remainingMs);
    res.send(this.landingPage(token, remainingLabel));
  }

  @Post('note/:token/reveal')
  async revealNote(@Param('token') token: string, @Res() res: Response) {
    const result = await this.service.revealAndDelete(token);
    if (!result) {
      res.status(404).json({ error: 'gone' });
      return;
    }
    res.json({ ciphertext: result.ciphertext });
  }

  private formatRemaining(ms: number): string {
    const h = Math.floor(ms / 3600000);
    const m = Math.floor((ms % 3600000) / 60000);
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
  }

  private landingPage(token: string, remaining: string): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Anti-Quantum Note</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{background:#111;color:#eee;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
    display:flex;align-items:center;justify-content:center;min-height:100vh;padding:20px}
  .card{background:#1e1e1e;border-radius:16px;padding:36px 28px;max-width:440px;width:100%;text-align:center;
    box-shadow:0 8px 32px rgba(0,0,0,0.5)}
  .icon{font-size:48px;margin-bottom:16px}
  h1{font-size:20px;font-weight:700;margin-bottom:8px;letter-spacing:0.3px}
  .sub{color:#888;font-size:14px;line-height:1.6;margin-bottom:28px}
  .btn{background:linear-gradient(135deg,#c0392b,#922b21);border:none;border-radius:10px;
    color:#fff;font-size:15px;font-weight:700;padding:14px 32px;cursor:pointer;width:100%;
    letter-spacing:0.3px;transition:opacity 0.2s}
  .btn:hover{opacity:0.9}
  .btn:disabled{opacity:0.5;cursor:not-allowed}
  .expires{color:#555;font-size:12px;margin-top:16px}
  .content{background:#151515;border:1px solid #333;border-radius:10px;padding:20px;
    text-align:left;line-height:1.7;font-size:14px;color:#ddd;word-break:break-word;
    white-space:pre-wrap;margin-bottom:16px}
  .revealed-header{color:#888;font-size:11px;text-transform:uppercase;letter-spacing:1px;margin-bottom:16px}
  .footer{color:#444;font-size:11px;margin-top:12px}
  #error{color:#e74c3c;font-size:13px;margin-top:12px;display:none}
</style>
</head>
<body>
<div class="card" id="landing">
  <div class="icon">⚛️</div>
  <h1>Anti-Quantum Note</h1>
  <p class="sub">Someone sent you a self-destructing message.<br>It will be permanently destroyed after you read it.</p>
  <button class="btn" id="revealBtn" onclick="reveal()">🔓 Reveal &amp; Destroy</button>
  <div class="expires">Expires in ${remaining} · Powered by Fireplace</div>
  <div id="error">Failed to load note. It may have already been read.</div>
</div>

<div class="card" id="revealed" style="display:none">
  <div class="icon">🔓</div>
  <div class="revealed-header">Message revealed · Now permanently destroyed</div>
  <div class="content" id="noteContent"></div>
  <div class="footer">This note has been deleted from the server.<br>Refreshing this page will show nothing.</div>
</div>

<script>
async function reveal() {
  const btn = document.getElementById('revealBtn');
  btn.disabled = true;
  btn.textContent = 'Decrypting...';

  try {
    const fragment = location.hash.slice(1);
    if (!fragment) throw new Error('No key in URL');

    const res = await fetch('/note/${token}/reveal', { method: 'POST' });
    if (!res.ok) throw new Error('gone');
    const { ciphertext } = await res.json();

    const keyBytes = base64ToBytes(fragment);
    const cryptoKey = await crypto.subtle.importKey(
      'raw', keyBytes, { name: 'AES-GCM' }, false, ['decrypt']
    );

    const parts = ciphertext.split(':');
    if (parts.length !== 2) throw new Error('bad format');
    const iv = base64ToBytes(parts[0]);
    const enc = base64ToBytes(parts[1]);

    const decrypted = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, cryptoKey, enc);
    const text = new TextDecoder().decode(decrypted);

    document.getElementById('landing').style.display = 'none';
    document.getElementById('noteContent').textContent = text;
    document.getElementById('revealed').style.display = '';
  } catch (e) {
    btn.disabled = false;
    btn.textContent = '🔓 Reveal & Destroy';
    document.getElementById('error').style.display = '';
  }
}

function base64ToBytes(b64) {
  const bin = atob(b64.replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from(bin, c => c.charCodeAt(0));
}
</script>
</body>
</html>`;
  }

  private destroyedPage(): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Anti-Quantum Note</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{background:#111;color:#eee;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
    display:flex;align-items:center;justify-content:center;min-height:100vh}
  .card{background:#1e1e1e;border-radius:16px;padding:36px 28px;max-width:440px;width:100%;
    text-align:center;box-shadow:0 8px 32px rgba(0,0,0,0.5)}
  .icon{font-size:48px;margin-bottom:16px}
  h1{font-size:18px;font-weight:700;margin-bottom:10px}
  p{color:#666;font-size:14px;line-height:1.6}
</style>
</head>
<body>
<div class="card">
  <div class="icon">💀</div>
  <h1>This note no longer exists</h1>
  <p>It was either already read or has expired.<br>Ask the sender to create a new one.</p>
</div>
</body>
</html>`;
  }
}
