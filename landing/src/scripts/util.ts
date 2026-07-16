// Shared math + canvas helpers for the landing page.
export interface Pt { x: number; y: number }

export const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
export const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
export const seg = (p: number, a: number, b: number) => clamp((p - a) / (b - a), 0, 1);
export const ease = (t: number) => t * t * (3 - 2 * t);
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const rnd = (s: string) => s[(Math.random() * s.length) | 0];
export const fake = (n: number) => Array.from({ length: n }, () => rnd(B64)).join('');
export const bez = (p1: Pt, cp: Pt, p2: Pt, t: number): Pt => {
  const q = 1 - t;
  return {
    x: q * q * p1.x + 2 * q * t * cp.x + t * t * p2.x,
    y: q * q * p1.y + 2 * q * t * cp.y + t * t * p2.y,
  };
};

/** Global pointer position in 0..1 viewport space (parallax input). */
export const mouse = { x: 0.5, y: 0.5 };
if (typeof window !== 'undefined') {
  window.addEventListener('pointermove', (e) => {
    mouse.x = e.clientX / innerWidth;
    mouse.y = e.clientY / innerHeight;
  });
}

/** Size a canvas to its CSS box (dpr-capped) and return a scaled 2D context. */
export function fit(canvas: HTMLCanvasElement): CanvasRenderingContext2D {
  const dpr = Math.min(devicePixelRatio || 1, 1.5);
  canvas.width = canvas.clientWidth * dpr;
  canvas.height = canvas.clientHeight * dpr;
  const ctx = canvas.getContext('2d')!;
  ctx.scale(dpr, dpr);
  return ctx;
}

export interface Star { x: number; y: number; r: number; tw: number; sp: number }
export const makeStars = (W: number, H: number, n: number): Star[] =>
  Array.from({ length: n }, () => ({
    x: Math.random() * W, y: Math.random() * H,
    r: Math.random() * 1.1 + 0.2, tw: Math.random() * 6.28, sp: 0.3 + Math.random() * 1.2,
  }));

export function drawStars(ctx: CanvasRenderingContext2D, stars: Star[], t: number, tint: string, par: number) {
  const dx = (mouse.x - 0.5) * par, dy = (mouse.y - 0.5) * par;
  for (const st of stars) {
    const a = 0.22 + 0.45 * Math.abs(Math.sin(st.tw + t * st.sp));
    ctx.beginPath();
    ctx.arc(st.x + dx * st.r, st.y + dy * st.r, st.r, 0, 6.28);
    ctx.fillStyle = `rgba(${tint},${a})`;
    ctx.fill();
  }
}

export function ring(ctx: CanvasRenderingContext2D, pos: Pt, t01: number, maxR: number, rgb: string) {
  if (t01 <= 0 || t01 >= 1) return;
  ctx.beginPath();
  ctx.arc(pos.x, pos.y, 6 + maxR * ease(t01), 0, 6.28);
  ctx.strokeStyle = `rgba(${rgb},${0.7 * (1 - t01)})`;
  ctx.lineWidth = 1.5 * (1 - t01) + 0.5;
  ctx.stroke();
}

export const rectC = (el: Element): Pt => {
  const r = el.getBoundingClientRect();
  return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
};
