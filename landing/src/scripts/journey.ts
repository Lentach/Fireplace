// The spine: scroll-driven journey of one message, from the Send click to
// "delivered" on the second device. The server stop is the RELAY MACHINE —
// unlike a real Enigma it transforms NOTHING: same ciphertext in and out.
//
// Mid-page integration: no scroll lock. Sending is interactive at the top of
// the section; if the visitor just keeps scrolling, the message auto-sends so
// the story always plays. Everything is a pure function of scroll progress
// (reversible), except the time-driven ambient stream/stars.
import { B64, bez, clamp, drawStars, ease, fake, fit, lerp, makeStars, rectC, ring, rnd, seg, type Pt } from './util';

declare global {
  interface Window { __journey?: { p: number; sent: boolean; landed: boolean } }
}

export function initJourney(section: HTMLElement) {
  const $ = <T extends HTMLElement = HTMLElement>(sel: string) => section.querySelector<T>(sel)!;
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
    el.style.transform = `translate(${x - 150 * s}px, ${y - h * s / 2}px) scale(${s})`;
    el.style.transformOrigin = `150px ${h / 2}px`;
    el.style.opacity = String(o);
  };

  function anchors() {
    const senderC = { x: W * 0.20, y: H * 0.66 };
    const recipC = { x: W * 0.80, y: H * 0.66 };
    const intake = rectC($('.slot.in'));
    const outlet = rectC($('.slot.out'));
    return {
      senderC, recipC, intake, outlet,
      sealP: { x: W * 0.38, y: H * 0.55 },
      liftStart: { x: W * 0.5 + 40, y: H * 0.60 + 60 },
      liftCp: { x: W * 0.45, y: H * 0.42 },
      cp1: { x: intake.x - 90, y: H * 0.52 },   // approach the IN slit from below — clear of the caption column
      cp2: { x: W * 0.74, y: H * 0.24 },
      holdP: { x: W * 0.60, y: H * 0.55 },      // the "watch it decrypt" spot: big, unhurried
      landPt: { x: recipC.x - 45, y: recipC.y + 25 },
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
  const draft = $<HTMLInputElement>('.compose input');
  const sendBtn = $<HTMLButtonElement>('.compose button');
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
      sealAt.push(0.16 + 0.12 * Math.random());
      openAt.push(0.82 + 0.09 * Math.random());   // decrypt during the held stage, staggered
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
    if (!sent && raw > 0.015) doSend(true);   // skimmer path: story plays anyway
    const p = sent ? raw : 0;
    window.__journey = { p, sent, landed };
    const A = anchors();

    ctx.clearRect(0, 0, W, H);
    drawStars(ctx, stars, t, '190,220,240', 16);

    const streamH = 170, loop = streamH + 50;
    for (const r of streamRows) {
      const y = streamH + 20 - ((t * r.sp + r.phase) % loop);
      r.el.style.transform = `translateY(${y}px)`;
      r.el.style.opacity = String(clamp(Math.min(y / 26, (streamH - y) / 26), 0, 0.85));
    }

    if (!sent) {
      phonePose($('.phone.sender'), W * 0.5, H * 0.60, 1, 1);
      ($('.phone.recipient')).style.opacity = '0';
      $('.prompt').style.opacity = '1';
      requestAnimationFrame(update);
      return;
    }
    $('.prompt').style.opacity = String(1 - seg(p, 0, 0.06));

    const pathAlpha = seg(p, 0.26, 0.34) * (1 - seg(p, 0.95, 1));
    if (pathAlpha > 0) {
      ctx.setLineDash([2, 7]);
      ctx.strokeStyle = `rgba(143,216,255,${0.28 * pathAlpha})`; ctx.lineWidth = 1;
      for (const [P1, CP, P2] of [[A.sealP, A.cp1, A.intake], [A.outlet, A.cp2, A.holdP]] as [Pt, Pt, Pt][]) {
        ctx.beginPath();
        for (let k = 0; k <= 40; k++) { const q = bez(P1, CP, P2, k / 40); k === 0 ? ctx.moveTo(q.x, q.y) : ctx.lineTo(q.x, q.y); }
        ctx.stroke();
      }
      ctx.setLineDash([]);
    }

    const moveOut = ease(seg(p, 0.02, 0.16));
    phonePose($('.phone.sender'), lerp(W * 0.5, A.senderC.x, moveOut), lerp(H * 0.60, A.senderC.y, moveOut), lerp(1, 0.58, moveOut), 1);
    const recIn = ease(seg(p, 0.60, 0.74));
    phonePose($('.phone.recipient'), lerp(W * 1.15, A.recipC.x, recIn), A.recipC.y, 0.58, recIn);

    const sk = $('.keytag.sender-key');
    sk.style.opacity = String(seg(p, 0.16, 0.20) * (1 - seg(p, 0.34, 0.40)));
    sk.style.left = `${A.senderC.x - 80}px`; sk.style.top = `${A.senderC.y + 190}px`;
    const rk = $('.keytag.recipient-key');
    rk.style.opacity = String(seg(p, 0.81, 0.85) * (1 - seg(p, 0.97, 1)));
    rk.style.left = `${A.recipC.x - 90}px`; rk.style.top = `${A.recipC.y + 190}px`;

    $('.machine').style.opacity = String(seg(p, 0.42, 0.48) * (1 - seg(p, 0.92, 0.98) * 0.7));
    const spin = ease(seg(p, 0.48, 0.68));
    rotors.forEach((r, i) => { r.style.transform = `rotate(${spin * (360 + i * 220) + t * 8}deg)`; });
    $('.scan-in').style.opacity = String(seg(p, 0.495, 0.515) * (1 - seg(p, 0.53, 0.55)));
    $('.scan-out').style.opacity = String(seg(p, 0.615, 0.635) * (1 - seg(p, 0.655, 0.675)));
    /* my row: slides IN through the intake side, joins the queue, then slides
       OUT the outlet side and vanishes as the machine relays it onward */
    const mine = $('.sv-row.mine');
    const dockT = ease(seg(p, 0.53, 0.58));
    const exitT = ease(seg(p, 0.615, 0.655));
    mine.style.opacity = String(dockT * (1 - exitT));
    mine.style.transform = `translate(${(1 - dockT) * -340 + exitT * 360}px, ${lerp(150, 76, dockT)}px)`;

    const tr = $('.traveler');
    let pos: Pt, scale = 1, capsule = false, inside = false;
    if (p < 0.16) {
      const t1 = ease(seg(p, 0.02, 0.16));
      pos = bez(A.liftStart, A.liftCp, A.sealP, t1);
      scale = lerp(1, 0.9, t1);
    } else if (p < 0.30) {
      pos = A.sealP; scale = 0.9;
    } else if (p < 0.50) {
      const t1 = ease(seg(p, 0.30, 0.50));
      pos = bez(A.sealP, A.cp1, A.intake, t1);
      scale = lerp(0.9, 0.58, ease(seg(p, 0.30, 0.38))); capsule = true;
    } else if (p < 0.545) {
      pos = A.intake; capsule = true;
      scale = 0.58 * (1 - ease(seg(p, 0.50, 0.545)));
    } else if (p < 0.615) {
      pos = A.intake; capsule = true; inside = true; scale = 0;
    } else if (p < 0.66) {
      pos = A.outlet; capsule = true;
      scale = 0.58 * ease(seg(p, 0.615, 0.66));
    } else if (p < 0.80) {
      const t2 = ease(seg(p, 0.66, 0.80));
      pos = bez(A.outlet, A.cp2, A.holdP, t2);
      scale = 0.58; capsule = true;
    } else if (p < 0.93) {
      // UNSEAL HOLD — grow large and decrypt char by char, unhurried
      pos = A.holdP;
      scale = lerp(0.58, 0.95, ease(seg(p, 0.80, 0.84)));
      capsule = p < 0.86;                       // capsule chrome fades as plaintext returns
    } else {
      const t3 = ease(seg(p, 0.93, 0.965));
      pos = { x: lerp(A.holdP.x, A.landPt.x, t3), y: lerp(A.holdP.y, A.landPt.y, t3) };
      scale = lerp(0.95, 0.62, t3);
    }

    if (p > 0.968 && !landed) { landed = true; $('.recipient-msgs').appendChild(landedBubble!); }
    if (p <= 0.968 && landed) { landed = false; landedBubble!.remove(); }
    if (sentMeta) sentMeta.textContent = p > 0.972 ? '08:12 ✓✓' : '08:12 ✓';

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

    ring(ctx, A.intake, seg(p, 0.49, 0.545), 40, '143,216,255');
    ring(ctx, A.outlet, seg(p, 0.615, 0.665), 40, '143,216,255');
    ring(ctx, A.holdP, seg(p, 0.795, 0.845), 44, '143,216,255');
    ring(ctx, A.landPt, seg(p, 0.958, 0.995), 34, '255,217,138');

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
