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

/* skip — a photon-pulse chevron in ONE fixed spot, the bottom-RIGHT corner (a
   peripheral control, not a central journey cue: dead-center it got mis-tapped).
   Bidirectional: ↓ skips forward to the two-device reply finale ("07 / Kate's
   turn"); once there it flips to ↑ and jumps back to the start. Hidden through the
   middle stretch, where the recipient flies through / docks in the corner. */
const skip = document.querySelector<HTMLButtonElement>('.skip-tour');
if (skip && journey) {
  const range = () => journey.offsetHeight - innerHeight;
  const rawOf = () => (scrollY - journey.offsetTop) / range();
  // the two-device reply finale sits near the tail of the 800vh track
  const finaleY = () => journey.offsetTop + range() * 0.97;
  skip.addEventListener('click', () => {
    if (rawOf() > 0.955) lenis.scrollTo(journey.offsetTop, { offset: 0 });   // ↑ back to the start
    else lenis.scrollTo(finaleY(), { offset: 0 });                            // ↓ to the reply
  });
  const syncSkip = () => {
    const raw = rawOf();
    const up = raw > 0.955 && raw < 1;         // at the reply finale → ↑
    const down = raw > 0.02 && raw < 0.66;     // the start (Bob) + mid-tour → ↓ to the reply finale
    skip.classList.toggle('show', up || down);
    skip.classList.toggle('up', up);
    skip.setAttribute('aria-label', up ? 'Back to the start' : 'Skip to the reply');
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

