// The relay node's canvas renderers — one visual family in one module: the
// dot-shell (the hero globe's language zoomed to ONE node of the network),
// the contained singularity glimpsed through it, the event horizon of the
// opened core, and the IN/OUT ports on the shell equator.
// Scroll owns every gate (the open/alpha inputs are pure functions of p,
// both directions); only the instability/spin textures are ambient time,
// the same class as the stars. `q` scales glow cost down for mobile —
// shadowBlur is the canvas hot path; dot density is never reduced.
import type { Pt } from './util';

/** One stroked arc with warm bloom — the shared idiom of every hot edge
 *  here: horizon ring, doppler arc, singularity ring, wandering hot-spot. */
function glowArc(ctx: CanvasRenderingContext2D, x: number, y: number, r: number, from: number, to: number, rgb: string, alpha: number, width: number, blur: number) {
  ctx.beginPath();
  ctx.arc(x, y, r, from, to);
  ctx.strokeStyle = `rgba(${rgb},${alpha})`;
  ctx.lineWidth = width;
  ctx.shadowColor = 'rgba(255,185,115,.95)';
  ctx.shadowBlur = blur;
  ctx.stroke();
  ctx.shadowBlur = 0;
}

// Opening = an iris: dots inside the aperture slide out to its rim and bunch
// there, reading as the cut edge of the parted shell around the exposed core.
export function makeShell(N = 500) {
  const pts: [number, number, number][] = [];
  for (let i = 0; i < N; i++) {
    const y = 1 - 2 * (i + 0.5) / N, r = Math.sqrt(1 - y * y), phi = i * 2.39996323;
    pts.push([Math.cos(phi) * r, y, Math.sin(phi) * r]);
  }
  const F = 2.6, tilt = 0.35, tc = Math.cos(tilt), tsn = Math.sin(tilt);
  return (ctx: CanvasRenderingContext2D, cx: number, cy: number, R: number, open: number, alpha: number, t: number) => {
    if (alpha <= 0.02 || R <= 2) return;
    const ang = t * 0.1, ca = Math.cos(ang), sa = Math.sin(ang);
    const g = ctx.createRadialGradient(cx, cy, R * 0.55, cx, cy, R * 1.55);
    g.addColorStop(0, `rgba(60,120,160,${0.10 * alpha})`);
    g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g;
    ctx.fillRect(cx - R * 1.6, cy - R * 1.6, R * 3.2, R * 3.2);
    // aperture slightly WIDER than the core's clip circle (journey keeps the
    // DOM core at coreR = R/1.16), so rim dots always sit outside the face
    const apR = open * R * 0.92;
    for (const [x0, y0, z0] of pts) {
      const xr = x0 * ca + z0 * sa, zr = -x0 * sa + z0 * ca;
      const yr = y0 * tc - zr * tsn, zt = y0 * tsn + zr * tc;
      const s = F / (F + zt);
      let px = xr * R * s, py = yr * R * s;
      let a = Math.max(0, 0.95 - (zt + 1) * 0.5) * alpha;
      const front = zt < 0;
      if (front) {
        const rho = Math.hypot(px, py);
        if (rho < apR) {
          // inside the iris: slide along the view ray to just past the rim —
          // deeper dots travel further and fade harder (the shell "dilates")
          const k = rho / Math.max(apR, 1);
          const f = (apR + 2 + (1 - k) * 5) / Math.max(rho, 0.5);
          px *= f; py *= f;
          a *= 0.35 + 0.65 * k;
        }
      } else {
        a *= 1 - open * 0.45;   // opened shell reads hollow from behind
      }
      if (a <= 0.02) continue;
      ctx.beginPath();
      ctx.arc(cx + px, cy + py, front ? 1.5 : 0.9, 0, 6.28);
      ctx.fillStyle = `rgba(143,216,255,${a})`;
      ctx.fill();
    }
  };
}

// The CONTAINED singularity: glimpsed through the closed shell — a small
// black hole that looks barely stable. Brightness is scroll-gated (a, from
// presence × sealed-ness); the instability texture — flicker, wander,
// flares, orbiting debris — is ambient time. Drawn UNDER the shell dots,
// so the lattice passes in front: caged.
export function drawSingularity(ctx: CanvasRenderingContext2D, cx: number, cy: number, r: number, a: number, t: number, q = 1) {
  if (a <= 0.02 || r <= 2) return;
  // irregular flicker (two beating sines) + slow breath + rare flare spikes
  const fl = 0.55 + 0.30 * Math.sin(t * 7.3) * Math.sin(t * 3.1 + 1.7) + 0.15 * Math.sin(t * 1.2);
  const flare = Math.pow(Math.max(0, Math.sin(t * 0.83 + 0.6)), 24);
  const jx = cx + 1.6 * Math.sin(t * 9.7), jy = cy + 1.6 * Math.cos(t * 8.3 + 2);
  const rw = r * (1 + 0.035 * Math.sin(t * 5.9) + 0.10 * flare);
  const glow = ctx.createRadialGradient(jx, jy, rw * 0.55, jx, jy, rw * (1.9 + 1.1 * flare));
  glow.addColorStop(0, 'rgba(0,0,0,0)');
  glow.addColorStop(0.3, `rgba(255,160,80,${(0.16 + 0.30 * flare) * fl * a})`);
  glow.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = glow;
  ctx.fillRect(jx - rw * 3.2, jy - rw * 3.2, rw * 6.4, rw * 6.4);
  // the hole itself — swallows even the shell's own light
  ctx.beginPath(); ctx.arc(jx, jy, rw, 0, 6.28);
  ctx.fillStyle = `rgba(0,0,0,${0.92 * a})`; ctx.fill();
  // flickering horizon ring + wandering doppler hot-spot
  glowArc(ctx, jx, jy, rw, 0, 6.28, '255,205,150', (0.55 + 0.35 * flare) * fl * a, 1.6 + 1.4 * flare, (12 + 26 * flare) * q);
  const da = t * 0.9;
  glowArc(ctx, jx, jy, rw, da, da + 1.5 + 0.7 * Math.sin(t * 2.3), '255,242,220', (0.5 + 0.5 * flare) * fl * a, 2.2 + 1.6 * flare, (18 + 30 * flare) * q);
  // debris sparks on tight decaying orbits
  for (let i = 0; i < 3; i++) {
    const sp = 1.6 + i * 0.53, ph = i * 2.1;
    const orr = rw * (1.25 + 0.18 * Math.sin(t * 0.7 + ph) + 0.12 * i);
    const ang = t * sp + ph;
    ctx.beginPath(); ctx.arc(jx + Math.cos(ang) * orr, jy + Math.sin(ang) * orr * 0.92, 1.3, 0, 6.28);
    ctx.fillStyle = `rgba(255,220,170,${0.8 * fl * a})`;
    ctx.shadowColor = 'rgba(255,185,115,.9)'; ctx.shadowBlur = 8 * q; ctx.fill(); ctx.shadowBlur = 0;
  }
}

// EVENT HORIZON of the opened core: the face swallows all light, so
// everything visible lives at the edge — a warm photon ring hugging the
// clip circle, doppler-bright on the approaching side, plus a soft
// accretion halo bleeding outward. Static per frame: p-keyed like the iris.
export function drawHorizon(ctx: CanvasRenderingContext2D, cx: number, cy: number, rr: number, a: number, q = 1) {
  if (a <= 0.02 || rr <= 2) return;
  const halo = ctx.createRadialGradient(cx, cy, rr * 0.78, cx, cy, rr * 1.62);
  halo.addColorStop(0, 'rgba(0,0,0,0)');
  halo.addColorStop(0.28, `rgba(255,178,102,${0.20 * a})`);
  halo.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = halo;
  ctx.fillRect(cx - rr * 1.7, cy - rr * 1.7, rr * 3.4, rr * 3.4);
  glowArc(ctx, cx, cy, rr, 0, 6.28, '255,214,166', 0.6 * a, 2.4, 22 * q);
  // doppler beaming: the side spinning toward the viewer burns brighter
  glowArc(ctx, cx, cy, rr, 2.2, 4.35, '255,240,218', 0.85 * a, 3.4, 34 * q);
}

// IN/OUT ports on the LIVE shell equator — ice slits + tags (the cold
// network family, not the warm accretion one); they flare while the
// traveler is scanned through.
export function drawPorts(ctx: CanvasRenderingContext2D, intake: Pt, outlet: Pt, a: number, scanIn: number, scanOut: number, q = 1) {
  if (a <= 0.02) return;
  ctx.font = '7px IBM Plex Mono'; ctx.textAlign = 'center';
  for (const [pt, lbl, scan] of [[intake, 'in', scanIn], [outlet, 'out', scanOut]] as [Pt, string, number][]) {
    const h = 8 + scan * 3;
    ctx.beginPath(); ctx.moveTo(pt.x, pt.y - h); ctx.lineTo(pt.x, pt.y + h);
    ctx.strokeStyle = `rgba(143,216,255,${(0.5 + 0.5 * scan) * a})`;
    ctx.lineWidth = 2 + scan * 1.5;
    ctx.shadowColor = 'rgba(143,216,255,.9)'; ctx.shadowBlur = scan * 14 * q;
    ctx.stroke(); ctx.shadowBlur = 0;
    ctx.fillStyle = `rgba(120,160,190,${0.8 * a})`;
    ctx.fillText(lbl, pt.x, pt.y + 22);
  }
  ctx.textAlign = 'left';
}
