// The relay node's dot-shell: the hero globe's visual language zoomed to ONE
// node of the network. Everything but the slow ambient spin is a pure
// function of (open, alpha) — scroll owns the choreography, both directions.
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
// flares, orbiting debris — is ambient time, same class as the stars.
// Drawn UNDER the shell dots, so the lattice passes in front: caged.
export function drawSingularity(ctx: CanvasRenderingContext2D, cx: number, cy: number, r: number, a: number, t: number) {
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
  // flickering horizon ring
  ctx.beginPath(); ctx.arc(jx, jy, rw, 0, 6.28);
  ctx.strokeStyle = `rgba(255,205,150,${(0.55 + 0.35 * flare) * fl * a})`;
  ctx.lineWidth = 1.6 + 1.4 * flare;
  ctx.shadowColor = 'rgba(255,180,110,.95)'; ctx.shadowBlur = 12 + 26 * flare;
  ctx.stroke();
  // wandering doppler hot-spot — the bright side never sits still
  const da = t * 0.9;
  ctx.beginPath(); ctx.arc(jx, jy, rw, da, da + 1.5 + 0.7 * Math.sin(t * 2.3));
  ctx.strokeStyle = `rgba(255,242,220,${(0.5 + 0.5 * flare) * fl * a})`;
  ctx.lineWidth = 2.2 + 1.6 * flare;
  ctx.shadowBlur = 18 + 30 * flare; ctx.stroke(); ctx.shadowBlur = 0;
  // debris sparks on tight decaying orbits
  for (let i = 0; i < 3; i++) {
    const sp = 1.6 + i * 0.53, ph = i * 2.1;
    const orr = rw * (1.25 + 0.18 * Math.sin(t * 0.7 + ph) + 0.12 * i);
    const ang = t * sp + ph;
    ctx.beginPath(); ctx.arc(jx + Math.cos(ang) * orr, jy + Math.sin(ang) * orr * 0.92, 1.3, 0, 6.28);
    ctx.fillStyle = `rgba(255,220,170,${0.8 * fl * a})`;
    ctx.shadowColor = 'rgba(255,190,120,.9)'; ctx.shadowBlur = 8; ctx.fill(); ctx.shadowBlur = 0;
  }
}
