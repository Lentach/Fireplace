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
  interface Window { __journey?: { p: number; sent: boolean; landed: boolean } }
}

/* ---- symmetric timeline (p ranges) ---- */
const T = {
  lift: [0.02, 0.15],
  sealHold: [0.15, 0.28],
  wire1: [0.28, 0.47],
  swallow: [0.47, 0.515],
  inside: [0.515, 0.585],
  emit: [0.585, 0.63],
  wire2: [0.63, 0.82],       // same length as wire1
  unsealHold: [0.82, 0.945], // same feel as sealHold
  drop: [0.945, 0.972],
  land: 0.972,
} as const;

export function initJourney(section: HTMLElement) {
  const $ = <E extends HTMLElement = HTMLElement>(sel: string) => section.querySelector<E>(sel)!;
  const canvas = $<HTMLCanvasElement>('canvas');
  let ctx = fit(canvas);
  let W = canvas.clientWidth, H = canvas.clientHeight;
  window.addEventListener('resize', () => { ctx = fit(canvas); W = canvas.clientWidth; H = canvas.clientHeight; });

  const stars = makeStars(W, H, 240);
  const trail: Pt[] = [];
  let sent = false, landed = false, plain = '';
  let cipherChars: string[] = [];
  let spans: HTMLSpanElement[] = [], sealAt: number[] = [], openAt: number[] = [];
  let sentMeta: HTMLElement | null = null, landedBubble: HTMLElement | null = null;

  const phonePose = (el: HTMLElement, x: number, y: number, s: number, o: number) => {
    const h = el.offsetHeight || 560;
    el.style.transform = `translate(${x - el.offsetWidth / 2 * s}px, ${y - h * s / 2}px) scale(${s})`;
    el.style.transformOrigin = `${el.offsetWidth / 2}px ${h / 2}px`;
    el.style.opacity = String(o);
  };

  function anchors() {
    const mobile = W < 700;
    const senderC = mobile ? { x: W * 0.26, y: H * 0.82 } : { x: W * 0.20, y: H * 0.66 };
    const recipC = mobile ? { x: W * 0.70, y: H * 0.82 } : { x: W * 0.80, y: H * 0.66 };
    const intake = rectC($('.slot.in'));
    const outlet = rectC($('.slot.out'));
    const holdY = mobile ? H * 0.66 : H * 0.55;
    return {
      mobile, senderC, recipC, intake, outlet,
      phoneS: mobile ? 0.5 : 0.58,
      sealP: { x: mobile ? W * 0.30 : W * 0.38, y: holdY },
      unsealP: { x: mobile ? W * 0.66 : W * 0.62, y: holdY },   // mirror of sealP
      liftStart: { x: W * 0.5 + (mobile ? 30 : 40), y: H * 0.60 + (mobile ? 40 : 60) },
      liftCp: { x: W * 0.45, y: H * 0.48 },
      dropCp: { x: W * 0.66, y: holdY - H * 0.03 },             // gentle mirror of the lift
      cp1: { x: intake.x - (mobile ? 40 : 90), y: H * (mobile ? 0.58 : 0.52) },
      cp2: { x: outlet.x + (mobile ? 40 : 90), y: H * (mobile ? 0.58 : 0.52) },  // mirror of cp1
      landPt: { x: recipC.x - (mobile ? 30 : 45), y: recipC.y + (mobile ? 15 : 25) },
      keyDy: mobile ? 140 : 190,
    };
  }

  /* machine window stream */
  const streamRows: { el: HTMLElement; phase: number; sp: number }[] = [];
  {
    const stream = $('.sv-stream');
    for (let i = 0; i < 9; i++) {
      const el = document.createElement('div');
      el.className = 'sv-row';
      const hh = 8 + ((Math.random() * 2) | 0), mm = (Math.random() * 60) | 0, ss = (Math.random() * 60) | 0;
      el.innerHTML = `<span class="t">${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}:${String(ss).padStart(2, '0')}</span>${Math.random() < 0.8 ? '2:' : '3:'}${fake(38)}`;
      stream.appendChild(el);
      streamRows.push({ el, phase: i * 46 + Math.random() * 18, sp: 13 + Math.random() * 5 });
    }
    const mine = document.createElement('div');
    mine.className = 'sv-row mine';
    stream.appendChild(mine);
  }
  const rotors = [...section.querySelectorAll<HTMLElement>('[data-rotor]')];

  /* send — manual (button/Enter) or auto (visitor scrolls past without clicking) */
  const draft = $<HTMLInputElement>('.phone.sender .compose input');
  const sendBtn = $<HTMLButtonElement>('.phone.sender .compose button');
  sendBtn.addEventListener('click', () => doSend(false));
  draft.addEventListener('keydown', (e) => { if (e.key === 'Enter') doSend(false); });

  function doSend(auto: boolean) {
    if (sent) return;
    sent = true;
    plain = (draft.value.trim() || 'meet me at eight').slice(0, 40);
    draft.disabled = true; sendBtn.disabled = true; sendBtn.style.opacity = '.4';

    const m = document.createElement('div');
    m.className = 'm me'; m.textContent = plain;
    sentMeta = document.createElement('div');
    sentMeta.className = 'meta'; sentMeta.textContent = '08:12 ✓';
    m.appendChild(sentMeta);
    $('.sender-msgs').appendChild(m);

    const total = 2 + Math.ceil(plain.length * 4 / 3) + 10;
    cipherChars = Array.from({ length: total }, (_, i) => i === 0 ? '3' : i === 1 ? ':' : rnd(B64));
    const tr = $('.traveler');
    tr.innerHTML = ''; spans = []; sealAt = []; openAt = [];
    for (let i = 0; i < total; i++) {
      const el = document.createElement('span');
      if (i < plain.length) el.textContent = plain[i];
      else { el.textContent = cipherChars[i]; el.className = 'x'; }
      tr.appendChild(el); spans.push(el);
      sealAt.push(0.16 + 0.10 * Math.random());   // scramble inside the seal hold
      openAt.push(0.83 + 0.10 * Math.random());   // unscramble inside the unseal hold — same dynamics
    }
    $('.sv-row.mine').innerHTML = `<span class="lbl">yours →</span><span class="t">08:12:03</span>${cipherChars.join('')}`;

    landedBubble = document.createElement('div');
    landedBubble.className = 'm them landing';
    landedBubble.textContent = plain;
    landedBubble.insertAdjacentHTML('beforeend', '<div class="meta">08:12</div>');

    if (!auto) $('.journey-hint').style.opacity = '1';
  }

  const caps = [...section.querySelectorAll<HTMLElement>('.cap')];
  const stops = [...section.querySelectorAll<HTMLElement>('.rail .stop')];

  function update() {
    const now = performance.now(), t = now / 1000;
    const top = section.offsetTop;
    const raw = clamp((scrollY - top) / (section.offsetHeight - innerHeight), 0, 1);
    if (!sent && raw > 0.015) doSend(true);
    const p = sent ? raw : 0;
    window.__journey = { p, sent, landed };
    const A = anchors();

    ctx.clearRect(0, 0, W, H);
    drawStars(ctx, stars, t, '190,220,240', 16);

    /* ambient stream flows bottom → top */
    const streamH = A.mobile ? 140 : 170, loop = streamH + 50;
    for (const r of streamRows) {
      const y = streamH + 20 - ((t * r.sp + r.phase) % loop);
      r.el.style.transform = `translateY(${y}px)`;
      r.el.style.opacity = String(clamp(Math.min(y / 26, (streamH - y) / 26), 0, 0.85));
    }

    if (!sent) {
      phonePose($('.phone.sender'), W * 0.5, H * 0.60, 1, 1);
      $('.phone.recipient').style.opacity = '0';
      $('.prompt').style.opacity = '1';
      requestAnimationFrame(update);
      return;
    }
    $('.prompt').style.opacity = String(1 - seg(p, 0, 0.06));

    /* dashed routes, mirrored */
    const pathAlpha = seg(p, 0.24, 0.32) * (1 - seg(p, 0.95, 1));
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

    /* phones */
    const moveOut = ease(seg(p, T.lift[0], T.lift[1]));
    phonePose($('.phone.sender'), lerp(W * 0.5, A.senderC.x, moveOut), lerp(H * 0.60, A.senderC.y, moveOut), lerp(1, A.phoneS, moveOut), 1);
    const recIn = ease(seg(p, 0.60, 0.74));
    phonePose($('.phone.recipient'), lerp(W * 1.15, A.recipC.x, recIn), A.recipC.y, A.phoneS, recIn);

    const sk = $('.keytag.sender-key');
    sk.style.opacity = String(seg(p, 0.15, 0.19) * (1 - seg(p, 0.32, 0.38)));
    sk.style.left = `${A.senderC.x - 80}px`; sk.style.top = `${A.senderC.y + A.keyDy}px`;
    const rk = $('.keytag.recipient-key');
    rk.style.opacity = String(seg(p, 0.83, 0.87) * (1 - seg(p, 0.96, 1)));
    rk.style.left = `${A.recipC.x - 90}px`; rk.style.top = `${A.recipC.y + A.keyDy}px`;

    /* machine */
    $('.machine').style.opacity = String(seg(p, 0.40, 0.46) * (1 - seg(p, 0.92, 0.98) * 0.7));
    const spin = ease(seg(p, T.swallow[0], T.wire2[0]));
    rotors.forEach((r, i) => { r.style.transform = `rotate(${spin * (360 + i * 220) + t * 8}deg)`; });
    $('.scan-in').style.opacity = String(seg(p, 0.465, 0.485) * (1 - seg(p, 0.50, 0.52)));
    $('.scan-out').style.opacity = String(seg(p, 0.585, 0.605) * (1 - seg(p, 0.625, 0.645)));

    /* my row: slides in at the bottom of the window, drifts UP with the flow
       like every other row, then fades away as the machine relays it on */
    const mine = $('.sv-row.mine');
    const inT = ease(seg(p, 0.50, 0.545));
    const driftT = seg(p, 0.545, 0.62);
    const fadeT = ease(seg(p, 0.60, 0.64));
    mine.style.opacity = String(inT * 0.95 * (1 - fadeT));
    mine.style.transform = `translate(${(1 - inT) * -360 + fadeT * 40}px, ${lerp(streamH * 0.66, streamH * 0.18, driftT)}px)`;

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
      scale = lerp(0.9, 0.58, ease(seg(p, 0.28, 0.36))); capsule = true;
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
      scale = lerp(0.58, 0.9, ease(seg(p, 0.74, 0.82))); capsule = true;   // grows on approach, mirror of wire1 shrink
    } else if (p < T.unsealHold[1]) {
      pos = A.unsealP; scale = 0.9;
      capsule = p < 0.85;                        // chrome fades as plaintext returns
    } else {
      const k = ease(seg(p, T.drop[0], T.drop[1]));
      pos = bez(A.unsealP, A.dropCp, A.landPt, k);
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

    ring(ctx, A.intake, seg(p, 0.46, 0.515), 40, '143,216,255');
    ring(ctx, A.outlet, seg(p, 0.585, 0.635), 40, '143,216,255');
    ring(ctx, A.landPt, seg(p, 0.965, 1), 34, '255,217,138');

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
    $('.journey-hint').style.opacity = sent && p > 0.005 && p < 0.02 ? '1' : '0';

    requestAnimationFrame(update);
  }
  update();
}
