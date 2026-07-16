// Hero: rotating fibonacci dot-sphere with 3D connection arcs.
// Drag to rotate (inertia, auto-spin resumes). Ctrl+scroll to zoom — plain
// scroll keeps scrolling the page (embedded-map convention; Lenis ignores
// ctrl+wheel, so the two never fight).
import { fit, makeStars, drawStars, clamp, lerp } from './util';

export function initGlobe(canvas: HTMLCanvasElement) {
  let ctx = fit(canvas);
  let W = canvas.clientWidth, H = canvas.clientHeight;
  window.addEventListener('resize', () => { ctx = fit(canvas); W = canvas.clientWidth; H = canvas.clientHeight; });

  const N = 850;
  const pts: [number, number, number][] = [];
  for (let i = 0; i < N; i++) {
    const y = 1 - 2 * (i + 0.5) / N, r = Math.sqrt(1 - y * y), phi = i * 2.39996323;
    pts.push([Math.cos(phi) * r, y, Math.sin(phi) * r]);
  }
  const pick = () => pts[(Math.random() * N) | 0];
  const arcs = Array.from({ length: 8 }, () => ({ p1: pick(), p2: pick(), u: Math.random(), sp: 0.002 + Math.random() * 0.003 }));
  const stars = makeStars(W, H, 240);
  const F = 2.6;

  let ang = 0, tilt = 0.38, zoom = 1, vel = 0, lastT = performance.now();
  let dragging = false, px0 = 0, py0 = 0, interacted = false;
  const geo = { cx: 0, cy: 0, R: 1 };
  const over = (e: { clientX: number; clientY: number }) => {
    const r = canvas.getBoundingClientRect();
    return Math.hypot(e.clientX - r.left - geo.cx, e.clientY - r.top - geo.cy) < geo.R * 1.3;
  };
  const ui = (e: Event) => (e.target as Element)?.closest?.('input, a, button, nav');

  window.addEventListener('pointerdown', (e) => {
    if (ui(e) || !over(e)) return;
    dragging = true; interacted = true; px0 = e.clientX; py0 = e.clientY; vel = 0;
  });
  window.addEventListener('pointermove', (e) => {
    document.body.style.cursor = dragging ? 'grabbing' : (over(e) && !ui(e) ? 'grab' : '');
    if (!dragging) return;
    const dx = e.clientX - px0, dy = e.clientY - py0;
    px0 = e.clientX; py0 = e.clientY;
    ang += dx * 0.005; vel = dx * 0.005;
    tilt = clamp(tilt + dy * 0.004, -1.2, 1.2);
  });
  window.addEventListener('pointerup', () => { dragging = false; });
  window.addEventListener('wheel', (e) => {
    if (!e.ctrlKey || !over(e)) return;          // plain scroll keeps scrolling the page
    e.preventDefault(); interacted = true;
    zoom = clamp(zoom * (e.deltaY < 0 ? 1.09 : 0.92), 0.55, 2.3);
  }, { passive: false });

  function proj(v: [number, number, number], R: number, cx: number, cy: number) {
    const [x, y, z] = v;
    const xr = x * Math.cos(ang) + z * Math.sin(ang), zr = -x * Math.sin(ang) + z * Math.cos(ang);
    const yr = y * Math.cos(tilt) - zr * Math.sin(tilt), zt = y * Math.sin(tilt) + zr * Math.cos(tilt);
    const s = F / (F + zt);
    return { x: cx + xr * R * s, y: cy + yr * R * s, z: zt };
  }
  const bez3 = (p1: number[], cp: number[], p2: number[], u: number): [number, number, number] => {
    const q = 1 - u;
    return [
      q * q * p1[0] + 2 * q * u * cp[0] + u * u * p2[0],
      q * q * p1[1] + 2 * q * u * cp[1] + u * u * p2[1],
      q * q * p1[2] + 2 * q * u * cp[2] + u * u * p2[2],
    ];
  };

  (function frame() {
    const now = performance.now(), t = now / 1000, dt = Math.min(50, now - lastT);
    lastT = now;
    if (!dragging) { vel *= 0.94; ang += vel + 0.00012 * dt; }
    const R = Math.min(W, H) * 0.36 * zoom, cx = W * 0.7, cy = H * 0.52;
    geo.cx = cx; geo.cy = cy; geo.R = R;
    ctx.clearRect(0, 0, W, H);
    drawStars(ctx, stars, t, '190,220,240', 16);
    const g = ctx.createRadialGradient(cx, cy, R * 0.6, cx, cy, R * 1.6);
    g.addColorStop(0, 'rgba(60,120,160,.10)'); g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g; ctx.fillRect(cx - R * 1.7, cy - R * 1.7, R * 3.4, R * 3.4);
    const zs = Math.pow(zoom, 0.7);
    for (const v of pts) {
      const p = proj(v, R, cx, cy);
      const a = Math.max(0, 0.95 - (p.z + 1) * 0.5);
      if (a <= 0.02) continue;
      ctx.beginPath(); ctx.arc(p.x, p.y, (p.z < 0 ? 1.4 : 0.8) * zs, 0, 6.28);
      ctx.fillStyle = `rgba(143,216,255,${a})`; ctx.fill();
    }
    for (const arc of arcs) {
      const m = [(arc.p1[0] + arc.p2[0]) / 2, (arc.p1[1] + arc.p2[1]) / 2, (arc.p1[2] + arc.p2[2]) / 2];
      const ml = Math.hypot(m[0], m[1], m[2]) || 1;
      const cp = [m[0] / ml * 1.5, m[1] / ml * 1.5, m[2] / ml * 1.5];
      ctx.beginPath();
      for (let k = 0; k <= 36; k++) {
        const p = proj(bez3(arc.p1, cp, arc.p2, k / 36), R, cx, cy);
        k === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y);
      }
      ctx.strokeStyle = 'rgba(174,228,255,.24)'; ctx.lineWidth = 0.8 * Math.sqrt(zoom); ctx.stroke();
      arc.u = (arc.u + arc.sp) % 1;
      const hp = proj(bez3(arc.p1, cp, arc.p2, arc.u), R, cx, cy);
      ctx.beginPath(); ctx.arc(hp.x, hp.y, 1.9 * Math.sqrt(zoom), 0, 6.28);
      ctx.fillStyle = `rgba(214,240,255,${hp.z < 0 ? 0.95 : 0.35})`;
      ctx.shadowColor = 'rgba(143,216,255,.9)'; ctx.shadowBlur = 9; ctx.fill(); ctx.shadowBlur = 0;
    }
    if (!interacted) {
      ctx.font = '10px IBM Plex Mono'; ctx.textAlign = 'center';
      ctx.fillStyle = `rgba(143,216,255,${0.35 + 0.2 * Math.sin(now / 500)})`;
      ctx.fillText('drag to rotate · ctrl+scroll to zoom', cx, Math.min(H - 16, cy + R + 28));
      ctx.textAlign = 'left';
    }
    requestAnimationFrame(frame);
  })();
}
