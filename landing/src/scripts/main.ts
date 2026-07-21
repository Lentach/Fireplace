import Lenis from 'lenis';
import { initGlobe } from './globe';
import { initEncrypt } from './encrypt';
import { initJourney } from './journey';
import { drawSingularity, makeShell } from './shell';
import { drawStars, fit, makeStars, rafOnScreen } from './util';
const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

/* smooth scroll — Lenis animates native window scroll, so the journey engine's
   scrollY reads stay correct; Lenis ignores ctrl+wheel (globe zoom unaffected) */
const lenis = new Lenis();
function raf(time: number) {
  lenis.raf(time);
  requestAnimationFrame(raf);
}
requestAnimationFrame(raf);

/* hero globe + encrypt demo */
const globeCanvas = document.querySelector<HTMLCanvasElement>('.hero canvas');
if (globeCanvas) initGlobe(globeCanvas);
document.querySelectorAll<HTMLElement>('[data-encrypt]').forEach(initEncrypt);

/* journey */
const journey = document.querySelector<HTMLElement>('.journey');
if (journey) initJourney(journey);

/* clicking the wordmark refreshes the page (owner request) */
document.querySelector<HTMLElement>('nav .mark')?.addEventListener('click', () => location.reload());

/* skip — a photon-pulse ↓ chevron pinned to the bottom-RIGHT corner (a peripheral
   control, not a central journey cue: dead-center it read as "continue" and got
   mis-tapped, skipping the whole tour). Jumps forward past the tour to the facts;
   hidden once the recipient device comes into play (the final third) — it flies
   through and docks in the lower-right corner, exactly where the skip sits. */
const skip = document.querySelector<HTMLButtonElement>('.skip-tour');
const features = document.querySelector<HTMLElement>('#features');
if (skip && journey && features) {
  skip.addEventListener('click', () => lenis.scrollTo(features, { offset: -40 }));
  const syncSkip = () => {
    const top = journey.offsetTop;
    // show only mid-tour: past the composing/lifting sender (≤~0.15) and before the
    // recipient emerges (≥~0.66) — both dock in the lower-right where the skip sits
    const range = journey.offsetHeight - innerHeight;
    const raw = (scrollY - top) / range;
    const inTour = raw > 0.16 && raw < 0.66;
    skip.classList.toggle('show', inTour);
  };
  syncSkip();
  window.addEventListener('scroll', syncSkip, { passive: true });
}

/* outro: the last relay — a SEALED node drifts on among the stars with a
   through-wire of ambient envelopes: the story ends, the network doesn't.
   Same renderers as the journey (shellDraw/drawSingularity), miniature. */
const outCanvas = document.querySelector<HTMLCanvasElement>('.outro canvas');
if (outCanvas) {
  let ctx = fit(outCanvas);
  let W = outCanvas.clientWidth, H = outCanvas.clientHeight;
  window.addEventListener('resize', () => { ctx = fit(outCanvas); W = outCanvas.clientWidth; H = outCanvas.clientHeight; stars = makeStars(W, H, 200); });
  let stars = makeStars(W, H, 200);
  const shellDraw = makeShell(300);
  function frame() {
    const t = reduce ? 0 : performance.now() / 1000;
    ctx.clearRect(0, 0, W, H);
    drawStars(ctx, stars, t, '190,220,240', 22);
    const cx = W * 0.82 + Math.sin(t * 0.05) * 10;
    const cy = H * 0.22 + Math.cos(t * 0.04) * 7;
    const r = Math.min(W, H) * 0.10;
    // the wire runs off both edges of the page — envelopes keep crossing
    const lg = ctx.createLinearGradient(0, 0, W, 0);
    lg.addColorStop(0, 'rgba(143,216,255,0)');
    lg.addColorStop(0.22, 'rgba(143,216,255,.10)');
    lg.addColorStop(0.78, 'rgba(143,216,255,.10)');
    lg.addColorStop(1, 'rgba(143,216,255,0)');
    ctx.beginPath(); ctx.moveTo(0, cy); ctx.lineTo(W, cy);
    ctx.strokeStyle = lg; ctx.lineWidth = 1.2; ctx.stroke();
    for (let i = 0; i < 3; i++) {
      const u = (t * 0.045 + i / 3) % 1;
      const x = u * W;
      if (Math.abs(x - cx) < r + 6) continue;   // swallowed by the node
      const fade = Math.sin(u * Math.PI);
      const g = ctx.createRadialGradient(x, cy, 0.5, x, cy, 6);
      g.addColorStop(0, `rgba(190,232,255,${0.5 * fade})`);
      g.addColorStop(1, 'rgba(143,216,255,0)');
      ctx.beginPath(); ctx.arc(x, cy, 6, 0, 6.28); ctx.fillStyle = g; ctx.fill();
    }
    drawSingularity(ctx, cx, cy, r * 0.34, 0.85, t, 0.7);
    shellDraw(ctx, cx, cy, r, 0, 0.85, t);
  }
  if (reduce) frame();
  else rafOnScreen(outCanvas, frame);
}

