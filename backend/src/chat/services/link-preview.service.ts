import { Injectable, Logger } from '@nestjs/common';

const PRIVATE_IP_RE =
  /^(localhost|127\.|10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|::1|fc00:|fd)/i;

function extractFirstUrl(text: string): string | null {
  const match = text.match(/https?:\/\/[^\s<>"{}|\\^`[\]]+/i);
  return match ? match[0] : null;
}

function isPrivateOrLocal(url: string): boolean {
  try {
    const { hostname } = new URL(url);
    return PRIVATE_IP_RE.test(hostname);
  } catch {
    return true;
  }
}

function parseOgMeta(html: string): {
  title: string | null;
  imageUrl: string | null;
} {
  const title =
    html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']/i)?.[1] ??
    html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']/i)?.[1] ??
    html.match(/<title[^>]*>([^<]+)<\/title>/i)?.[1] ??
    null;

  const imageUrl =
    html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i)?.[1] ??
    html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i)?.[1] ??
    null;

  return {
    title: title ? title.trim().substring(0, 200) : null,
    imageUrl: imageUrl ? imageUrl.trim() : null,
  };
}

@Injectable()
export class LinkPreviewService {
  private readonly logger = new Logger(LinkPreviewService.name);

  async fetchPreview(
    text: string,
  ): Promise<{ url: string; title: string | null; imageUrl: string | null } | null> {
    const url = extractFirstUrl(text);
    if (!url) return null;
    if (isPrivateOrLocal(url)) return null;

    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 5000);

      const response = await fetch(url, {
        signal: controller.signal,
        headers: { 'User-Agent': 'Mozilla/5.0 (compatible; ChatBot/1.0)' },
      });
      clearTimeout(timeout);

      if (!response.ok) return null;

      const contentType = response.headers.get('content-type') ?? '';
      if (!contentType.includes('text/html')) return null;

      // Read until </head> found (covers sites like YouTube with large inline JS)
      // or until 800KB safety limit to avoid unbounded downloads.
      const reader = response.body?.getReader();
      if (!reader) return null;
      let html = '';
      let totalBytes = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        totalBytes += value.byteLength;
        html += new TextDecoder().decode(value);
        if (html.includes('</head>')) break;
        if (totalBytes > 800_000) break;
      }
      reader.cancel();

      const { title, imageUrl } = parseOgMeta(html);
      if (!title && !imageUrl) return null;

      return { url, title, imageUrl };
    } catch (err) {
      this.logger.debug(`Link preview fetch failed for ${url}: ${err.message}`);
      return null;
    }
  }
}
