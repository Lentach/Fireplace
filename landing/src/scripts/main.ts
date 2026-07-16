import Lenis from 'lenis';
import { initGlobe } from './globe';
import { initEncrypt } from './encrypt';
import { initJourney } from './journey';
import { drawStars, fit, makeStars } from './util';

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

/* outro starfield */
const outCanvas = document.querySelector<HTMLCanvasElement>('.outro canvas');
if (outCanvas) {
  let ctx = fit(outCanvas);
  let W = outCanvas.clientWidth, H = outCanvas.clientHeight;
  window.addEventListener('resize', () => { ctx = fit(outCanvas); W = outCanvas.clientWidth; H = outCanvas.clientHeight; stars = makeStars(W, H, 200); });
  let stars = makeStars(W, H, 200);
  (function frame() {
    ctx.clearRect(0, 0, W, H);
    drawStars(ctx, stars, performance.now() / 1000, '190,220,240', 22);
    requestAnimationFrame(frame);
  })();
}

/* nav flips dark→light while the light zone is under it */
const nav = document.querySelector('nav');
const lightZone = document.getElementById('lightZone');
if (nav && lightZone) {
  const check = () => {
    const r = lightZone.getBoundingClientRect();
    nav.classList.toggle('on-light', r.top < 70 && r.bottom > 0);
    requestAnimationFrame(check);
  };
  check();
}
