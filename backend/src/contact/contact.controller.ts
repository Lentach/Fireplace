// backend/src/contact/contact.controller.ts
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  NotFoundException,
  Post,
  Query,
  Res,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { randomBytes } from 'crypto';
import type { Response } from 'express';
import { ContactService } from './contact.service';
import { CreateContactDto } from './dto/create-contact.dto';
import { SubscribeInboxDto } from './dto/subscribe-inbox.dto';

// Escape untrusted text for HTML interpolation (visitor-controlled messages).
const escapeHtml = (s: string): string =>
  s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

@Controller('contact')
export class ContactController {
  constructor(private readonly contactService: ContactService) {}

  // Public (the landing page has no auth). Abuse surface is bounded by the
  // per-IP throttle + honeypot + length caps; worst case is rows in a table.
  @Post()
  @Throttle({ default: { limit: 5, ttl: 900000 } }) // 5 per 15 min per IP
  @HttpCode(HttpStatus.NO_CONTENT)
  async create(@Body() dto: CreateContactDto): Promise<void> {
    // Honeypot filled -> bot. Pretend success so it learns nothing.
    if (dto.website) return;

    const message = dto.message.trim();
    if (!message) throw new BadRequestException('message must not be empty');

    const replyTo = dto.replyTo?.trim() || null;
    await this.contactService.create(message, replyTo);
  }

  // ---------- Owner inbox (key-guarded, account-independent) ----------

  // 404 (not 403) on a bad key: the inbox should be indistinguishable from a
  // nonexistent route to anyone without the bookmark.
  @Get('inbox')
  @Throttle({ default: { limit: 60, ttl: 60000 } })
  async inbox(@Query('key') key: string, @Res() res: Response): Promise<void> {
    if (!this.contactService.inboxKeyValid(key)) throw new NotFoundException();
    const messages = await this.contactService.listMessages();
    const nonce = randomBytes(16).toString('base64');
    res.setHeader(
      'Content-Security-Policy',
      `default-src 'self'; script-src 'nonce-${nonce}'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; manifest-src 'self'; base-uri 'none'`,
    );
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Robots-Tag', 'noindex, nofollow');

    const rows = messages
      .map((m) => {
        const when = new Date(m.createdAt).toISOString().replace('T', ' ').slice(0, 16);
        const reply = m.replyTo
          ? `<div class="reply">reply-to: ${escapeHtml(m.replyTo)}</div>`
          : '';
        return `<article><header><span>#${m.id}</span><time>${when} UTC</time></header><p>${escapeHtml(m.message)}</p>${reply}</article>`;
      })
      .join('');

    res.send(`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Fireplace Inbox">
<link rel="manifest" href="/contact/manifest.webmanifest?key=${encodeURIComponent(key)}">
<link rel="apple-touch-icon" href="/icons/notification-icon-512.png">
<title>Fireplace · contact inbox</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; background: #05090d; color: #eef6fb; font-family: 'IBM Plex Mono', ui-monospace, monospace; }
  main { max-width: 640px; margin: 0 auto; padding: 24px 16px 64px; }
  h1 { font-size: 11px; letter-spacing: .24em; text-transform: uppercase; color: rgba(143,216,255,.72); font-weight: 600; }
  .bar { display: flex; justify-content: space-between; align-items: center; gap: 12px; margin-bottom: 18px; }
  #notify { cursor: pointer; font: inherit; font-size: 10px; letter-spacing: .16em; text-transform: uppercase;
    color: #04121c; background: #8fd8ff; border: 0; border-radius: 999px; padding: 7px 14px; }
  #notify[disabled] { opacity: .55; cursor: default; }
  article { background: rgba(10,16,22,.7); border: 1px solid rgba(143,216,255,.18); padding: 12px 14px; margin-bottom: 10px; }
  article header { display: flex; justify-content: space-between; font-size: 9px; letter-spacing: .18em;
    text-transform: uppercase; color: rgba(143,216,255,.45); margin-bottom: 8px; }
  article p { margin: 0; font-size: 14px; line-height: 1.55; white-space: pre-wrap; word-break: break-word; }
  .reply { margin-top: 8px; font-size: 11px; color: rgba(143,216,255,.6); word-break: break-all; }
  .empty { opacity: .5; font-size: 13px; }
</style>
</head>
<body>
<main>
  <div class="bar">
    <h1>Contact inbox · ${messages.length}</h1>
    <button id="notify" type="button">Enable notifications</button>
  </div>
  ${rows || '<p class="empty">no messages yet</p>'}
</main>
<script nonce="${nonce}">
(function () {
  var btn = document.getElementById('notify');
  var KEY = ${JSON.stringify(key)};
  var VAPID = ${JSON.stringify(process.env.WEB_PUSH_VAPID_PUBLIC_KEY ?? '')};
  function b64ToU8(s) {
    var pad = '='.repeat((4 - (s.length % 4)) % 4);
    var raw = atob((s + pad).replace(/-/g, '+').replace(/_/g, '/'));
    var arr = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
    return arr;
  }
  function setLabel(t, done) { btn.textContent = t; if (done) btn.disabled = true; }
  if (!('serviceWorker' in navigator) || !('PushManager' in window) || !VAPID) {
    setLabel('Push unsupported here', true);
    return;
  }
  navigator.serviceWorker.register('/contact/sw.js').then(function (reg) {
    return reg.pushManager.getSubscription().then(function (sub) {
      if (sub) setLabel('Notifications on ✓', true);
    });
  }).catch(function () {});
  btn.addEventListener('click', function () {
    setLabel('Enabling…', false);
    navigator.serviceWorker.register('/contact/sw.js')
      .then(function (reg) { return navigator.serviceWorker.ready.then(function () { return reg; }); })
      .then(function (reg) {
        return Notification.requestPermission().then(function (perm) {
          if (perm !== 'granted') throw new Error('denied');
          return reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64ToU8(VAPID) });
        });
      })
      .then(function (sub) {
        var j = sub.toJSON();
        return fetch('/contact/subscribe', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ key: KEY, endpoint: sub.endpoint, p256dh: j.keys.p256dh, auth: j.keys.auth })
        }).then(function (r) { if (!r.ok) throw new Error('save'); });
      })
      .then(function () { setLabel('Notifications on ✓', true); })
      .catch(function (e) {
        setLabel(e && e.message === 'denied' ? 'Permission denied' : 'Failed — retry', false);
      });
  });
})();
</script>
</body>
</html>`);
  }

  // The SW carries no secrets (payload-driven), so it is served unguarded —
  // registration needs a stable, key-free URL anyway.
  @Get('sw.js')
  @Throttle({ default: { limit: 60, ttl: 60000 } })
  serviceWorker(@Res() res: Response): void {
    res.setHeader('Content-Type', 'application/javascript; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.send(`self.addEventListener('push', function (event) {
  var d = {};
  try { d = event.data ? event.data.json() : {}; } catch {}
  event.waitUntil(self.registration.showNotification(d.title || 'Contact form', {
    body: d.body || 'New message',
    icon: '/icons/notification-icon-512.png',
    badge: '/icons/notification-badge-96.png',
    tag: 'contact-inbox',
    renotify: true,
    data: { url: d.url || '/contact/inbox' }
  }));
});
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var url = (event.notification.data && event.notification.data.url) || '/contact/inbox';
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (all) {
    for (var i = 0; i < all.length; i++) {
      if (all[i].url.indexOf('/contact/inbox') !== -1) return all[i].focus();
    }
    return clients.openWindow(url);
  }));
});
`);
  }

  // iOS 16.4+ delivers Web Push ONLY to home-screen web apps, and "Add to
  // Home Screen" needs a manifest with standalone display to install as one.
  // start_url embeds the key so the icon opens straight into the inbox.
  @Get('manifest.webmanifest')
  @Throttle({ default: { limit: 60, ttl: 60000 } })
  manifest(@Query('key') key: string, @Res() res: Response): void {
    if (!this.contactService.inboxKeyValid(key)) throw new NotFoundException();
    res.setHeader('Content-Type', 'application/manifest+json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.send(
      JSON.stringify({
        name: 'Fireplace Inbox',
        short_name: 'Inbox',
        start_url: `/contact/inbox?key=${key}`,
        scope: '/contact/',
        display: 'standalone',
        background_color: '#05090d',
        theme_color: '#05090d',
        icons: [
          {
            src: '/icons/notification-icon-512.png',
            sizes: '512x512',
            type: 'image/png',
          },
        ],
      }),
    );
  }

  @Post('subscribe')
  @Throttle({ default: { limit: 10, ttl: 900000 } })
  @HttpCode(HttpStatus.NO_CONTENT)
  async subscribe(@Body() dto: SubscribeInboxDto): Promise<void> {
    if (!this.contactService.inboxKeyValid(dto.key)) {
      throw new NotFoundException();
    }
    await this.contactService.subscribe(dto.endpoint, dto.p256dh, dto.auth);
  }
}
