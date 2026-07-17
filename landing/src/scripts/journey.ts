// The spine: scroll-driven journey of one message, from the Send click to
// "delivered" on the second device. The server stop is the RELAY MACHINE —
// unlike a real Enigma it transforms NOTHING: same ciphertext in and out.
//
// The two sides are deliberately SYMMETRIC: lift→seal-hold→wire mirrors
// wire→unseal-hold→drop, with equal durations and the same scramble dynamics.
// Everything is a pure function of scroll progress p (reversible); only the
// ambient stream/stars are time-driven.
//
// Mid-page integration: no scroll lock. Sending is interactive at the top of
// the section; if the visitor just keeps scrolling, the message auto-sends.
import { B64, bez, clamp, drawStars, ease, fake, fit, lerp, makeStars, rectC, ring, rnd, seg, type Pt } from './util';

declare global {
  interface Window { __journey?: { p: number; sent: boolean; landed: boolean; raw0: number } }
}

/* ---- symmetric timeline (p ranges) ----
   The relay act owns ~23% of the track (owner-tuned: doubled first, then
   trimmed 25% — long enough to showcase, short enough to keep moving).
   Symmetry invariants: wire1 == wire2, sealHold == unsealHold, swallow == emit. */
const T = {
  lift: [0.02, 0.14],
  sealHold: [0.14, 0.26],
  wire1: [0.26, 0.43],
  swallow: [0.43, 0.475],
  inside: [0.475, 0.615],    // the ride through the window
  emit: [0.615, 0.66],       // same length as swallow
  wire2: [0.66, 0.83],       // same length as wire1
  unsealHold: [0.83, 0.95],  // same length as sealHold
  drop: [0.95, 0.972],
  land: 0.972,
} as const;

export function initJourney(section: HTMLElement) {
  const $ = <E extends HTMLElement = HTMLElement>(sel: string) => section.querySelector<E>(sel)!;
  const canvas = $<HTMLCanvasElement>('canvas');
  let ctx = fit(canvas);
  let W = canvas.clientWidth, H = canvas.clientHeight;
  window.addEventListener('resize', () => { ctx = fit(canvas); W = canvas.clientWidth; H = canvas.clientHeight; stars = makeStars(W, H, 240); });

  let stars = makeStars(W, H, 240);
  const trail: Pt[] = [];
  let sent = false, landed = false, plain = '';
  let raw0 = 0;      // raw scroll progress at the moment of send — p normalizes over the remainder
  let lastRaw = 0;
  let maxP = 0;      // how deep this send's journey got — gates the reverse-reset
  let cipherChars: string[] = [];
  let spans: HTMLSpanElement[] = [], sealAt: number[] = [], openAt: number[] = [];
  let sentMeta: HTMLElement | null = null, landedBubble: HTMLElement | null = null;
  let sentBubble: HTMLElement | null = null;

  const phonePose = (el: HTMLElement, x: number, y: number, s: number, o: number) => {
    const h = el.offsetHeight || 560;
    el.style.transform = `translate(${x - el.offsetWidth / 2 * s}px, ${y - h * s / 2}px) scale(${s})`;
    el.style.transformOrigin = `${el.offsetWidth / 2}px ${h / 2}px`;
    el.style.opacity = String(o);
  };

  function anchors() {
    const mobile = W < 700;
    // phonePose keeps the visual bottom at y + h/2 regardless of scale
    // (center-origin compensation), so clearances use the UNSCALED height.
    const ph = $('.phone.sender').offsetHeight || 560;
    const railTop = $('.rail').getBoundingClientRect().top || H;
    // Mobile: the phone is the protagonist on each side — top-center and LARGE
    // (sender through the seal, recipient through the unseal/finale); the
    // machine owns the middle act and fades out before the recipient arrives.
    // Desktop: anchored at 0.66H but pulled up on tall/short screens so the
    // phone AND the keytag under it always clear the rail.
    const sideY = mobile ? H * 0.40 : Math.min(H * 0.66, railTop - ph / 2 - 56);
    const senderC = mobile ? { x: W * 0.5, y: sideY } : { x: W * 0.20, y: sideY };
    const recipC = mobile ? { x: W * 0.5, y: sideY } : { x: W * 0.80, y: sideY };
    const intake = rectC($('.slot.in'));
    const outlet = rectC($('.slot.out'));
    const holdY = mobile ? H * 0.76 : H * 0.55;
    // Clean mirrored wire curves: leave the hold horizontally, bend up into
    // the slit. Single-bend quadratics, symmetric by construction.
    const sealP = { x: mobile ? W * 0.5 : W * 0.38, y: holdY };
    const unsealP = { x: mobile ? W * 0.5 : W * 0.62, y: holdY };
    return {
      mobile, senderC, recipC, intake, outlet, sealP, unsealP,
      // Desktop hold scale adapts to the free band between the caption
      // column (~0.15H + 270px) and the rail: on short screens the phone
      // shrinks instead of colliding with caption above or keytag/rail below
      // (visual top = bottom - ph*s, since the visual bottom is scale-free).
      phoneS: mobile ? 0.68 : clamp((railTop - 56 - (H * 0.15 + 270)) / ph, 0.34, 0.58),
      liftStart: { x: W * 0.5 + (mobile ? 30 : 40), y: H * 0.60 + (mobile ? 40 : 60) },
      liftCp: mobile ? { x: W * 0.30, y: H * 0.64 } : { x: W * 0.45, y: H * 0.48 },
      dropCp: mobile ? { x: W * 0.66, y: H * 0.58 } : { x: W * 0.66, y: holdY - H * 0.03 },
      cp1: { x: (sealP.x + intake.x) / 2, y: sealP.y },
      cp2: { x: (unsealP.x + outlet.x) / 2, y: unsealP.y },
      // keytag always sits BELOW the device: half height + margin
      keyDy: ph / 2 + 16,
    };
  }

  /* machine window stream — uniform speed + even spacing: a queue, no lapping.
     Each row periodically "refreshes" with a NEW envelope: fresh timestamp +
     a staggered hero-style re-scramble. The machine never rewrites anything —
     the slot just shows the next arrival. The visitor's own row stays frozen. */
  const stamp = () => {
    const hh = 8 + ((Math.random() * 2) | 0), mm = (Math.random() * 60) | 0, ss = (Math.random() * 60) | 0;
    return `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}:${String(ss).padStart(2, '0')}`;
  };
  type Cell = { el: HTMLSpanElement; final: string; settleAt: number };
  const streamRows: { el: HTMLElement; idx: number; tEl: HTMLSpanElement; cells: Cell[]; nextAt: number }[] = [];
  const STREAM_SP = 14;
  let mineSlot = -1;   // queue slot my row takes over while inside the machine (picked at entry)
  {
    const stream = $('.sv-stream');
    for (let i = 0; i < 9; i++) {
      const el = document.createElement('div');
      el.className = 'sv-row';
      const tEl = document.createElement('span');
      tEl.className = 't'; tEl.textContent = stamp();
      el.appendChild(tEl);
      const prefix = Math.random() < 0.8 ? '2:' : '3:';
      const cells: Cell[] = [];
      for (let c = 0; c < 40; c++) {
        const s = document.createElement('span');
        const final = c < 2 ? prefix[c] : rnd(B64);
        s.textContent = final;
        el.appendChild(s);
        cells.push({ el: s, final, settleAt: 0 });
      }
      stream.appendChild(el);
      streamRows.push({ el, idx: i, tEl, cells, nextAt: performance.now() + 1000 + Math.random() * 6000 });
    }
    const mine = document.createElement('div');
    mine.className = 'sv-row mine';
    stream.appendChild(mine);
    // "yours →" marker lives OUTSIDE the clipped stream, pinned to the
    // machine's left edge (over the IN slot) and tracks the row each frame.
    const tag = document.createElement('span');
    tag.className = 'mine-tag';
    tag.textContent = 'yours →';
    $('.machine').appendChild(tag);
  }
  const rotors = [...section.querySelectorAll<HTMLElement>('[data-rotor]')];

  /* send — manual (button/Enter) or auto (visitor scrolls past without clicking) */
  const draft = $<HTMLInputElement>('.phone.sender .compose input');
  const sendBtn = $<HTMLButtonElement>('.phone.sender .compose button');
  sendBtn.addEventListener('click', () => doSend(false));
  draft.addEventListener('keydown', (e) => { if (e.key === 'Enter') doSend(false); });
  // click/tap the compose → whole draft selected, one keystroke replaces it
  draft.addEventListener('focus', () => draft.select());
  // hero "type something private" box and this compose are the SAME draft —
  // last writer wins, until the message is sent
  document.addEventListener('fp:plain', (e) => {
    if (!sent) draft.value = (e as CustomEvent<string>).detail.slice(0, 40);
  });

  function doSend(auto: boolean) {
    if (sent) return;
    sent = true;
    raw0 = Math.min(lastRaw, 0.06);   // clamp: a teleport-scroll must not compress the track
    // empty input falls back to the PREVIOUS message (a replay without
    // retyping resends "your" message), then to the default
    plain = (draft.value.trim() || plain || 'meet me at eight').slice(0, 40);
    // like a real chat: the message leaves the input and lives in the thread
    draft.value = '';
    draft.disabled = true; sendBtn.disabled = true; sendBtn.style.opacity = '.4';

    sentBubble = document.createElement('div');
    sentBubble.className = 'm me'; sentBubble.textContent = plain;
    sentMeta = document.createElement('div');
    sentMeta.className = 'meta'; sentMeta.textContent = '08:12 ✓';
    sentBubble.appendChild(sentMeta);
    $('.sender-msgs').appendChild(sentBubble);

    const total = 2 + Math.ceil(plain.length * 4 / 3) + 10;
    cipherChars = Array.from({ length: total }, (_, i) => i === 0 ? '3' : i === 1 ? ':' : rnd(B64));
    const tr = $('.traveler');
    tr.innerHTML = ''; spans = []; sealAt = []; openAt = [];
    for (let i = 0; i < total; i++) {
      const el = document.createElement('span');
      if (i < plain.length) el.textContent = plain[i];
      else { el.textContent = cipherChars[i]; el.className = 'x'; }
      tr.appendChild(el); spans.push(el);
      sealAt.push(0.15 + 0.09 * Math.random());   // scramble inside the seal hold
      openAt.push(0.84 + 0.09 * Math.random());   // unscramble inside the unseal hold — same dynamics
    }
    // clamped AND padded to the ambient rows' 40 chars so it blends into the
    // queue no matter the message length — only the "yours →" tag gives it away
    $('.sv-row.mine').innerHTML = `<span class="t">08:12:03</span>${(cipherChars.join('') + fake(40)).slice(0, 40)}`;

    landedBubble = document.createElement('div');
    landedBubble.className = 'm them landing';
    landedBubble.textContent = plain;
    landedBubble.insertAdjacentHTML('beforeend', '<div class="meta">08:12</div>');

    if (!auto) $('.journey-hint').style.opacity = '1';
  }

  /* scroll all the way back to the top → the send undoes: the bubble lifts
     out of the thread, the compose unlocks EMPTY (type something new), and
     the whole journey can be replayed with a fresh message */
  function resetSend() {
    sent = false; landed = false; maxP = 0;
    sentBubble?.remove(); sentBubble = null; sentMeta = null;
    landedBubble?.remove(); landedBubble = null;
    draft.value = '';
    draft.disabled = false; sendBtn.disabled = false; sendBtn.style.opacity = '';
    const tr = $('.traveler');
    tr.innerHTML = ''; tr.style.opacity = '0';
    spans = [];
  }

  const caps = [...section.querySelectorAll<HTMLElement>('.cap')];
  const stops = [...section.querySelectorAll<HTMLElement>('.rail .stop')];

  function update() {
    const now = performance.now(), t = now / 1000;
    const top = section.offsetTop;
    const raw = clamp((scrollY - top) / (section.offsetHeight - innerHeight), 0, 1);
    lastRaw = raw;
    // roomy top zone: the visitor can stop and type; skimmers auto-send.
    // p restarts from 0 at the send point (no mid-lift pop on auto-send).
    // NEVER auto-send while the compose is focused — after a device-reset the
    // visitor sits ON the boundary, and keyboard/scroll drift must not fire a
    // half-typed message. Blur + scroll = replay as usual.
    if (!sent && raw > 0.06 && document.activeElement !== draft) doSend(true);
    // reverse back to the send point (phone docked at its start pose) → the
    // send undoes and the compose reopens. The gates share the boundary but
    // cannot oscillate: reset requires maxP > 0.05, and resetSend zeroes maxP,
    // so a fresh boundary-jitter send can't immediately un-send itself.
    if (sent && maxP > 0.05 && raw <= raw0) resetSend();
    const p = sent ? clamp((raw - raw0) / (1 - raw0), 0, 1) : 0;
    maxP = Math.max(maxP, p);
    window.__journey = { p, sent, landed, raw0 };
    const A = anchors();

    ctx.clearRect(0, 0, W, H);
    drawStars(ctx, stars, t, '190,220,240', 16);

    /* ambient stream flows bottom → top */
    const streamH = A.mobile ? 140 : 170, loop = streamH + 50;
    const visN = A.mobile ? 7 : 9;
    /* my row is a REAL queue member: at entry it takes over whichever slot
       currently sits in the lower-visible zone — that ambient row yields and
       mine adopts its exact phase, so spacing, speed, drift, edge-fade, and
       even the wrap all match the flow. It slides in through IN, climbs with
       the queue, and slides out through OUT before the capsule re-emerges —
       the mirror of how it entered. */
    const rowY = (idx: number) => streamH + 20 - ((t * STREAM_SP + idx * (loop / visN)) % loop);
    const mineIn = ease(seg(p, 0.46, 0.505));
    const mineOut = ease(seg(p, 0.585, 0.63));
    const minePres = Math.min(mineIn, 1 - mineOut);
    if (minePres <= 0) mineSlot = -1;
    else if (mineSlot < 0) {
      let best = Infinity;
      for (let i = 0; i < visN; i++) {
        const d = Math.abs(rowY(i) - streamH * 0.72);
        if (d < best) { best = d; mineSlot = i; }
      }
    }
    let mineFlowY = streamH * 0.5;
    for (const r of streamRows) {
      if (r.idx >= visN) { r.el.style.opacity = '0'; continue; }
      const y = rowY(r.idx);
      if (r.idx === mineSlot) mineFlowY = y;
      r.el.style.transform = `translateY(${y}px)`;
      r.el.style.opacity = String(clamp(Math.min(y / 26, (streamH - y) / 26), 0, 0.85) * (r.idx === mineSlot ? 1 - minePres : 1));
      // slot refresh: a NEW envelope takes the row — fresh stamp, staggered scramble
      if (now >= r.nextAt) {
        r.nextAt = now + 2500 + Math.random() * 6000;
        r.tEl.textContent = stamp();
        for (let c = 2; c < r.cells.length; c++) {
          r.cells[c].final = rnd(B64);
          r.cells[c].settleAt = now + 120 + Math.random() * 520;
        }
      }
      for (const cell of r.cells) {
        if (cell.settleAt > now) { cell.el.textContent = rnd(B64); cell.el.className = 'hot'; }
        else if (cell.el.className) { cell.el.textContent = cell.final; cell.el.className = ''; }
      }
    }

    if (!sent) {
      phonePose($('.phone.sender'), W * 0.5, H * 0.60, 1, 1);
      $('.phone.recipient').style.opacity = '0';
      $('.prompt').style.opacity = '1';
      requestAnimationFrame(update);
      return;
    }
    $('.prompt').style.opacity = String(1 - seg(p, 0, 0.035));

    /* dashed routes, mirrored */
    const pathAlpha = seg(p, 0.22, 0.30) * (1 - seg(p, 0.95, 1));
    if (pathAlpha > 0) {
      ctx.setLineDash([2, 7]);
      ctx.strokeStyle = `rgba(143,216,255,${0.28 * pathAlpha})`; ctx.lineWidth = 1;
      for (const [P1, CP, P2] of [[A.sealP, A.cp1, A.intake], [A.outlet, A.cp2, A.unsealP]] as [Pt, Pt, Pt][]) {
        ctx.beginPath();
        for (let k = 0; k <= 40; k++) { const q = bez(P1, CP, P2, k / 40); k === 0 ? ctx.moveTo(q.x, q.y) : ctx.lineTo(q.x, q.y); }
        ctx.stroke();
      }
      ctx.setLineDash([]);
    }

    /* phones — the journey ends the way it began: a full-size device.
       The recipient arrives small for the unseal, then GROWS to match the
       opening shot as the message lands. */
    const grow = ease(seg(p, 0.945, 0.985));
    const rpX = lerp(
      lerp(W * (A.mobile ? 1.35 : 1.15), A.recipC.x, ease(seg(p, A.mobile ? 0.72 : 0.62, A.mobile ? 0.82 : 0.76))),
      W * (A.mobile ? 0.5 : 0.62), grow);
    const rpY = lerp(A.recipC.y, H * (A.mobile ? 0.58 : 0.56), grow);
    const rpS = lerp(A.phoneS, A.mobile ? 1 : 0.95, grow);
    const recIn = ease(seg(p, A.mobile ? 0.70 : 0.60, A.mobile ? 0.80 : 0.74));
    phonePose($('.phone.recipient'), rpX, rpY, rpS, recIn);
    const landPt = { x: rpX - 60 * rpS, y: rpY + 12 * rpS };   // tracks the growing phone's chat area
    if (A.mobile) {
      const toTop = ease(seg(p, T.lift[0], T.lift[1]));
      const exitL = ease(seg(p, 0.26, 0.36));   // fully out before the capsule crosses its lane
      phonePose($('.phone.sender'),
        lerp(lerp(W * 0.5, A.senderC.x, toTop), -W * 0.35, exitL),
        lerp(H * 0.60, A.senderC.y, toTop),
        lerp(1, A.phoneS, toTop), 1);
    } else {
      const moveOut = ease(seg(p, T.lift[0], T.lift[1]));
      phonePose($('.phone.sender'), lerp(W * 0.5, A.senderC.x, moveOut), lerp(H * 0.60, A.senderC.y, moveOut), lerp(1, A.phoneS, moveOut), 1);
    }

    const sk = $('.keytag.sender-key');
    sk.style.opacity = String(seg(p, 0.14, 0.18) * (1 - seg(p, A.mobile ? 0.25 : 0.30, A.mobile ? 0.29 : 0.36)));
    sk.style.left = `${A.senderC.x - sk.offsetWidth / 2}px`; sk.style.top = `${A.senderC.y + A.keyDy}px`;
    const rk = $('.keytag.recipient-key');
    rk.style.opacity = String(seg(p, 0.84, 0.88) * (1 - seg(p, 0.925, 0.95)));
    rk.style.left = `${A.recipC.x - rk.offsetWidth / 2}px`; rk.style.top = `${A.recipC.y + A.keyDy}px`;

    /* machine */
    $('.machine').style.opacity = String(seg(p, 0.36, 0.42) * (A.mobile ? 1 - seg(p, 0.67, 0.75) : 1 - seg(p, 0.90, 0.96)));
    const spin = ease(seg(p, T.swallow[0], T.wire2[0]));
    rotors.forEach((r, i) => { r.style.transform = `rotate(${spin * (360 + i * 220) + t * 8}deg)`; });
    $('.scan-in').style.opacity = String(seg(p, 0.425, 0.445) * (1 - seg(p, 0.46, 0.48)));
    $('.scan-out').style.opacity = String(seg(p, 0.615, 0.635) * (1 - seg(p, 0.655, 0.675)));

    const mine = $('.sv-row.mine');
    const mineO = clamp(Math.min(mineFlowY / 26, (streamH - mineFlowY) / 26), 0, 0.85) * minePres;
    mine.style.opacity = String(mineO);
    mine.style.transform = `translate(${(1 - mineIn) * -360 + mineOut * 360}px, ${mineFlowY}px)`;
    const mineTag = $('.mine-tag');
    const streamR = $('.sv-stream').getBoundingClientRect();
    const machR = $('.machine').getBoundingClientRect();
    mineTag.style.top = `${streamR.top - machR.top + mineFlowY}px`;
    mineTag.style.opacity = String(mineO);

    /* traveler — symmetric two-act structure */
    const tr = $('.traveler');
    let pos: Pt, scale = 1, capsule = false, inside = false;
    if (p < T.lift[1]) {
      const k = ease(seg(p, T.lift[0], T.lift[1]));
      pos = bez(A.liftStart, A.liftCp, A.sealP, k);
      scale = lerp(1, 0.9, k);
    } else if (p < T.sealHold[1]) {
      pos = A.sealP; scale = 0.9;
    } else if (p < T.wire1[1]) {
      const k = ease(seg(p, T.wire1[0], T.wire1[1]));
      pos = bez(A.sealP, A.cp1, A.intake, k);
      scale = lerp(0.9, 0.58, ease(seg(p, 0.26, 0.38))); capsule = true;
    } else if (p < T.swallow[1]) {
      pos = A.intake; capsule = true;
      scale = 0.58 * (1 - ease(seg(p, T.swallow[0], T.swallow[1])));
    } else if (p < T.inside[1]) {
      pos = A.intake; capsule = true; inside = true; scale = 0;
    } else if (p < T.emit[1]) {
      pos = A.outlet; capsule = true;
      scale = 0.58 * ease(seg(p, T.emit[0], T.emit[1]));
    } else if (p < T.wire2[1]) {
      const k = ease(seg(p, T.wire2[0], T.wire2[1]));
      pos = bez(A.outlet, A.cp2, A.unsealP, k);
      scale = lerp(0.58, 0.9, ease(seg(p, 0.71, 0.83))); capsule = true;   // grows on approach, mirror of wire1 shrink
    } else if (p < T.unsealHold[1]) {
      pos = A.unsealP; scale = 0.9;
      capsule = p < 0.86;                        // chrome fades as plaintext returns
    } else {
      const k = ease(seg(p, T.drop[0], T.drop[1]));
      pos = bez(A.unsealP, A.dropCp, landPt, k);
      scale = lerp(0.9, 0.62, k);
    }

    if (p > T.land && !landed) { landed = true; $('.recipient-msgs').appendChild(landedBubble!); }
    if (p <= T.land && landed) { landed = false; landedBubble!.remove(); }
    if (sentMeta) sentMeta.textContent = p > 0.975 ? '08:12 ✓✓' : '08:12 ✓';

    tr.classList.toggle('capsule', capsule);
    tr.style.opacity = String(seg(p, 0.015, 0.04) * (landed || inside ? 0 : 1));
    tr.style.transform = `translate(${pos.x - tr.offsetWidth / 2}px, ${pos.y - tr.offsetHeight / 2}px) scale(${Math.max(scale, 0.001)})`;

    if (capsule && !landed && !inside && scale > 0.2) {
      trail.unshift({ x: pos.x, y: pos.y });
      if (trail.length > 14) trail.pop();
      for (let i = 1; i < trail.length; i++) {
        ctx.beginPath(); ctx.arc(trail[i].x, trail[i].y, 3.4 * (1 - i / trail.length), 0, 6.28);
        ctx.fillStyle = `rgba(143,216,255,${0.30 * (1 - i / trail.length)})`; ctx.fill();
      }
      ctx.beginPath(); ctx.arc(pos.x, pos.y, 16, 0, 6.28);
      const gg = ctx.createRadialGradient(pos.x, pos.y, 2, pos.x, pos.y, 16);
      gg.addColorStop(0, 'rgba(143,216,255,.5)'); gg.addColorStop(1, 'rgba(143,216,255,0)');
      ctx.fillStyle = gg; ctx.fill();
    } else if (trail.length) trail.pop();

    ring(ctx, A.intake, seg(p, 0.42, 0.475), 40, '143,216,255');
    ring(ctx, A.outlet, seg(p, 0.615, 0.665), 40, '143,216,255');
    ring(ctx, landPt, seg(p, 0.965, 1), 34, '255,217,138');

    /* char states — seal and unseal share the same staggered mechanics */
    for (let i = 0; i < spans.length; i++) {
      const el = spans[i];
      const sealed = p >= sealAt[i] && p < openAt[i];
      const isGrow = i >= plain.length;
      if (sealed) {
        el.className = Math.abs(p - sealAt[i]) < 0.015 || Math.abs(p - openAt[i]) < 0.015 ? 'hot' : '';
        el.style.display = 'inline'; el.textContent = cipherChars[i];
      } else if (isGrow) {
        el.className = 'x'; el.style.display = 'none';
      } else {
        el.className = p > 0.5 && Math.abs(p - openAt[i]) < 0.02 ? 'hot' : '';
        el.style.display = 'inline'; el.textContent = plain[i];
      }
    }

    for (const c of caps) {
      const a = +c.dataset.a!, b = +c.dataset.b!;
      c.style.opacity = String(seg(p, a, a + 0.03) * (1 - seg(p, b - 0.03, b)));
      c.style.transform = `translateY(${(1 - seg(p, a, a + 0.05)) * 18}px)`;
    }
    $('.rail').style.opacity = p > 0.015 ? '1' : '0';
    stops.forEach((s) => s.classList.toggle('on', p >= +s.dataset.p!));
    $('.journey-hint').style.opacity = sent && p > 0.005 && p < 0.04 ? '1' : '0';

    requestAnimationFrame(update);
  }
  update();
}
