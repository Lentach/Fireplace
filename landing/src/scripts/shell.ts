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
