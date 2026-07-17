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
import { makeShell } from './shell';

declare global {
  interface Window { __journey?: { p: number; sent: boolean; landed: boolean; raw0: number; dir: number } }
}

const DEFAULT_MSG = 'sending very sensitive data — safe here';

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
// the reply journey lands on the sender at the mirror point of T.land
const REV_LAND = 1 - T.land;

export function initJourney(section: HTMLElement) {
  const $ = <E extends HTMLElement = HTMLElement>(sel: string) => section.querySelector<E>(sel)!;
  const canvas = $<HTMLCanvasElement>('canvas');
  let ctx = fit(canvas);
  let W = canvas.clientWidth, H = canvas.clientHeight;
  window.addEventListener('resize', () => { ctx = fit(canvas); W = canvas.clientWidth; H = canvas.clientHeight; stars = makeStars(W, H, 240); });

  let stars = makeStars(W, H, 240);
  const trail: Pt[] = [];
  let sent = false, landed = false, plain = '';
  let dir: 1 | -1 = 1;   // the traveler's direction: 1 you→her, -1 her reply→you
  let raw0 = 0;      // raw scroll progress at the moment of send — p normalizes over the remainder
  let lastRaw = 0;
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

  function anchors(p: number) {
    const mobile = W < 700;
    // phonePose keeps the visual bottom at y + h/2 regardless of scale
    // (center-origin compensation), so clearances use the UNSCALED height.
    const ph = $('.phone.sender').offsetHeight || 560;
    const pw = $('.phone.sender').offsetWidth || 300;
    const railTop = $('.rail').getBoundingClientRect().top || H;
    // Mobile: the phone is the protagonist on each side — top-center and LARGE
    // (sender through the seal, recipient through the unseal/finale); the
    // machine owns the middle act and fades out before the recipient arrives.
    // Desktop: anchored at 0.66H but pulled up on tall/short screens so the
    // phone AND the keytag under it always clear the rail.
    const sideY = mobile ? H * 0.40 : Math.min(H * 0.66, railTop - ph / 2 - 56);
    const senderC = mobile ? { x: W * 0.5, y: sideY } : { x: W * 0.20, y: sideY };
    const recipC = mobile ? { x: W * 0.5, y: sideY } : { x: W * 0.80, y: sideY };
    // the relay node: sphere geometry derived from the DOM core's box — the
    // dot-shell wraps it, the IN/OUT ports sit on the shell's equator, and
    // the wires plug in there. The radius follows the journey: materializes
    // mid-size, grows to full for the act, and (desktop) shrinks back to a
    // sealed mini that lingers where the machine used to sit.
    const coreEl = $('.core');
    const coreC = rectC(coreEl);
    const coreR = (coreEl.offsetWidth || 300) / 2;
    const grow = ease(seg(p, 0.33, 0.425));
    const shrink = mobile ? 0 : ease(seg(p, 0.71, 0.78));
    const shellR = coreR * 1.16 * (0.55 + 0.45 * grow) * (1 - 0.55 * shrink);
    const intake = { x: coreC.x - shellR, y: coreC.y };
    const outlet = { x: coreC.x + shellR, y: coreC.y };
    const holdY = mobile ? H * 0.76 : H * 0.55;
    // Clean mirrored wire curves: leave the hold horizontally, bend up into
    // the shell port. Single-bend quadratics, symmetric by construction.
    const sealP = { x: mobile ? W * 0.5 : W * 0.38, y: holdY };
    const unsealP = { x: mobile ? W * 0.5 : W * 0.62, y: holdY };
    return {
      mobile, senderC, recipC, intake, outlet, sealP, unsealP, coreC, coreR, shellR,
      // Desktop hold scale adapts to the free band between the caption
      // column (~0.15H + 270px) and the rail: on short screens the phone
      // shrinks instead of colliding with caption above or keytag/rail below
      // (visual top = bottom - ph*s, since the visual bottom is scale-free).
      phoneS: mobile ? 0.68 : clamp((railTop - 56 - (H * 0.15 + 270)) / ph, 0.34, 0.58),
      // Desktop finale: both devices dock center-stage as LARGE as fits —
      // width-limited so they can never collide (centers 0.30W apart, 24px
      // gap), height-limited so the top edge clears the nav.
      finS: mobile ? 1 : clamp(Math.min((W * 0.30 - 24) / pw, (H * 0.56 + ph / 2 - 76) / ph), 0.55, 1.2),
      finSx: W * 0.35, finRx: W * 0.65,
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
    for (let i = 0; i < 18; i++) {
      const el = document.createElement('div');
      el.className = 'sv-row';
      const tEl = document.createElement('span');
      tEl.className = 't'; tEl.textContent = stamp();
      el.appendChild(tEl);
      const prefix = Math.random() < 0.8 ? '2:' : '3:';
      const cells: Cell[] = [];
      for (let c = 0; c < 60; c++) {
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
  const shellDraw = makeShell();

  /* send — manual (button/Enter) or auto (visitor scrolls past without clicking) */
  const draft = $<HTMLInputElement>('.phone.sender .compose input');
  const sendBtn = $<HTMLButtonElement>('.phone.sender .compose button');
  const caret = $('.phone.sender .c-caret');
  const draftR = $<HTMLInputElement>('.phone.recipient .compose input');
  const sendBtnR = $<HTMLButtonElement>('.phone.recipient .compose button');
  const caretR = $('.phone.recipient .c-caret');
  const hintEl = $('.journey-hint');
  sendBtn.addEventListener('click', () => doSend(false));
  draft.addEventListener('keydown', (e) => { if (e.key === 'Enter') doSend(false); });
  sendBtnR.addEventListener('click', () => doSendBack());
  draftR.addEventListener('keydown', (e) => { if (e.key === 'Enter') doSendBack(); });
  // click/tap a compose → whole draft selected, one keystroke replaces it
  draft.addEventListener('focus', () => draft.select());
  draftR.addEventListener('focus', () => draftR.select());
  // hero "type something private" box and this compose are the SAME draft —
  // last writer wins, whenever the phone is docked
  document.addEventListener('fp:plain', (e) => {
    if (docked()) draft.value = (e as CustomEvent<string>).detail.slice(0, 120);
  });
  // composers are POSITION-locked, not send-locked: each is live whenever its
  // phone is docked — the sender at the start of the track, the recipient at
  // the delivered end (that's where the reply journey launches from).
  const pOf = () => sent ? clamp((lastRaw - raw0) / (1 - raw0), 0, 1) : 0;
  const docked = () => !sent || pOf() <= 0.02;
  const dockedR = () => sent && pOf() >= 0.95;

  /* the traveler carries whatever was sent LAST, in either direction */
  function buildTraveler(prefix: string, ts: string) {
    const total = 2 + Math.ceil(plain.length * 4 / 3) + 10;
    cipherChars = Array.from({ length: total }, (_, i) => i < 2 ? prefix[i] : rnd(B64));
    const tr = $('.traveler');
    // same wrap width as the real bubble → the detaching copy is its twin
    tr.style.maxWidth = `${sentBubble!.offsetWidth}px`;
    tr.innerHTML = ''; spans = []; sealAt = []; openAt = [];
    for (let i = 0; i < total; i++) {
      const el = document.createElement('span');
      if (i < plain.length) el.textContent = plain[i];
      else { el.textContent = cipherChars[i]; el.className = 'x'; }
      tr.appendChild(el); spans.push(el);
      sealAt.push(0.15 + 0.09 * Math.random());   // scramble inside the seal hold
      openAt.push(0.84 + 0.09 * Math.random());   // unscramble inside the unseal hold — same dynamics
    }
    // clamped AND padded to the ambient rows' 60 chars so it blends into the
    // queue no matter the message length — only the "yours →" tag gives it away
    $('.sv-row.mine').innerHTML = `<span class="t">${ts}</span>${(cipherChars.join('') + fake(60)).slice(0, 60)}`;
  }

  // like a real chat the thread STACKS: the oldest bubbles fall away the
  // moment the column would overflow into the compose panel
  const trimThread = (thread: HTMLElement) => {
    while (thread.scrollHeight > thread.clientHeight + 1 && thread.children.length > 1) thread.firstElementChild!.remove();
  };
  const stack = (thread: HTMLElement, el: HTMLElement) => {
    thread.appendChild(el);
    trimThread(thread);
  };

  function doSend(auto: boolean) {
    if (sent && auto) return;         // auto-send only arms the FIRST journey
    if (!docked()) return;            // in flight — the message can't change
    const typed0 = draft.value.trim();
    if (sent && !typed0) return;      // real chat: an empty send is a no-op
    sent = true; dir = 1; landed = false;   // a delivered reply stays behind as history
    raw0 = Math.min(lastRaw, 0.06);   // clamp: a teleport-scroll must not compress the track
    // every send stacks a fresh bubble — a real chat happily repeats the
    // same text. (Scroll-replays never pass through here, so no dupe spam.)
    plain = (typed0 || plain || DEFAULT_MSG).slice(0, 120);
    // like a real chat: the message leaves the input and lives in the thread
    draft.value = '';

    sentBubble = document.createElement('div');
    sentBubble.className = 'm me'; sentBubble.textContent = plain;
    sentMeta = document.createElement('div');
    sentMeta.className = 'meta'; sentMeta.textContent = '08:12 ✓';
    sentBubble.appendChild(sentMeta);
    stack($('.sender-msgs'), sentBubble);

    buildTraveler('3:', '08:12:03');

    landedBubble = document.createElement('div');
    landedBubble.className = 'm them landing';
    landedBubble.textContent = plain;
    landedBubble.insertAdjacentHTML('beforeend', '<div class="meta">08:12</div>');

    hintEl.textContent = 'scroll — your message is on its way ↓';
    if (!auto) hintEl.style.opacity = '1';
  }

  /* the reply: typed on HER phone at the delivered end of the track, it flies
     the SAME rail backwards — scroll up and every stage plays in mirror.
     No default text here: an empty reply is a no-op, silence stays silence. */
  function doSendBack(crossed = false) {
    // launches only from the delivered end — the CROSSING is the proof for
    // implicit sends (a fast flick may land many frames past the drop point)
    if (!crossed && !dockedR()) return;
    const typed = draftR.value.trim();
    if (!typed) return;
    dir = -1; landed = false;         // the delivered original stays behind as history
    plain = typed.slice(0, 120);
    draftR.value = '';

    sentBubble = document.createElement('div');
    sentBubble.className = 'm me'; sentBubble.textContent = plain;
    sentMeta = document.createElement('div');
    sentMeta.className = 'meta'; sentMeta.textContent = '08:13 ✓';
    sentBubble.appendChild(sentMeta);
    stack($('.recipient-msgs'), sentBubble);

    buildTraveler('2:', '08:13:07');  // in-session ratchet envelope, not a PreKey one

    landedBubble = document.createElement('div');
    landedBubble.className = 'm them landing';
    landedBubble.textContent = plain;
    landedBubble.insertAdjacentHTML('beforeend', '<div class="meta">08:13</div>');

    hintEl.textContent = 'scroll up — the reply is on its way ↑';
  }


  const caps = [...section.querySelectorAll<HTMLElement>('.cap')];
  const stops = [...section.querySelectorAll<HTMLElement>('.rail .stop')];

  function update() {
    const now = performance.now(), t = now / 1000;
    // self-heal on any viewport change the resize event missed (devtools
    // device-toolbar toggles can land before layout settles)
    if (canvas.clientWidth !== W || canvas.clientHeight !== H) {
      ctx = fit(canvas); W = canvas.clientWidth; H = canvas.clientHeight; stars = makeStars(W, H, 240);
    }
    const top = section.offsetTop;
    const raw = clamp((scrollY - top) / (section.offsetHeight - innerHeight), 0, 1);
    const prevRaw = lastRaw;
    lastRaw = raw;
    // roomy top zone: the visitor can stop and type; skimmers auto-send once.
    // p restarts from 0 at the send point (no mid-lift pop on auto-send).
    // NEVER auto-send while the compose is focused — keyboard/scroll drift
    // must not fire a half-typed message. Blur + scroll = journey as usual.
    if (!sent && raw > 0.06 && document.activeElement !== draft) doSend(true);
    // scrolling past lift-off with a freshly typed draft = implicit send —
    // the journey ALWAYS flies the newest message, no button needed (exactly
    // like the first-visit auto-send). Crossing-triggered so fast flicks
    // can't skip it; disarm + re-arm keeps the p-normalization clean.
    const liftRaw = raw0 + 0.02 * (1 - raw0);
    if (sent && prevRaw <= liftRaw && raw > liftRaw && draft.value.trim() && document.activeElement !== draft) {
      sent = false;
      doSend(true);
    }
    // the mirror: scrolling UP past the drop point with a freshly typed reply
    // launches the reverse journey — no button needed
    const dropRaw = raw0 + 0.98 * (1 - raw0);
    if (sent && prevRaw >= dropRaw && raw < dropRaw && draftR.value.trim() && document.activeElement !== draftR) doSendBack(true);
    const p = sent ? clamp((raw - raw0) / (1 - raw0), 0, 1) : 0;
    // the composer locks by POSITION: live whenever the phone is docked,
    // locked only while the message is actually in flight. A focused input
    // is NEVER disabled — mobile keyboard-open scroll drift must not kick
    // the visitor out mid-type (doSend itself is docked-gated anyway).
    const lock = sent && p > 0.02 && document.activeElement !== draft;
    if (draft.disabled !== lock) {
      draft.disabled = lock; sendBtn.disabled = lock;
      sendBtn.style.opacity = lock ? '.4' : '';
    }
    // her composer unlocks at the delivered end — that's HER dock
    const lockR = !(sent && p >= 0.98) && document.activeElement !== draftR;
    if (draftR.disabled !== lockR) {
      draftR.disabled = lockR; sendBtnR.disabled = lockR;
      sendBtnR.style.opacity = lockR ? '.4' : '';
    }
    // ONE typing invitation at a time: each fake caret blinks only in ITS
    // empty, typable, unfocused compose — the two unlock windows can never
    // overlap, so at most one caret is ever visible (focused inputs get the
    // native caret)
    caret.classList.toggle('off', !(draft.value === '' && !lock && document.activeElement !== draft));
    caretR.classList.toggle('off', !(draftR.value === '' && !lockR && document.activeElement !== draftR));
    // reversing ALL the way out (crossing into the very top) clears both
    // inputs — a stale message must not greet the next pass. Transition-
    // triggered, so nobody's active typing is ever stomped.
    if (raw <= 0.005 && prevRaw > 0.005) {
      if (document.activeElement !== draft) {
        draft.value = '';
        document.dispatchEvent(new CustomEvent('fp:clear'));
      }
      if (document.activeElement !== draftR) draftR.value = '';
    }
    window.__journey = { p, sent, landed, raw0, dir };
    const A = anchors(p);

    ctx.clearRect(0, 0, W, H);
    drawStars(ctx, stars, t, '190,220,240', 16);

    /* ambient stream flows bottom → top, filling the WHOLE core: each row's
       width follows the sphere's chord at its height — short slivers at the
       poles, widest at the equator — so the text lives INSIDE the volume */
    const streamEl = $('.sv-stream');
    const streamH = streamEl.clientHeight || (A.mobile ? 140 : 170);
    const coreHalf = streamEl.clientWidth / 2;
    const faceR = ($('.core').offsetWidth || 300) / 2 - 8;   // stay inside the clip face
    const rowH = streamRows[0].el.offsetHeight || 15;
    const loop = streamH + 50;
    const visN = Math.min(streamRows.length, Math.max(5, Math.round(loop / (A.mobile ? 27 : 26))));
    const chord = (yTop: number) => {
      const dy = yTop + rowH / 2 - streamH / 2;
      return Math.sqrt(Math.max(faceR * faceR - dy * dy, 1));
    };
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
      const ch = chord(y);
      r.el.style.left = `${coreHalf - ch}px`;
      r.el.style.width = `${2 * ch}px`;
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

    /* the relay node — a dot-shell around the core: materializes mid-size on
       approach, grows to full, parts open for the message, seals after it
       leaves. Desktop keeps a sealed mini-sphere behind; mobile fades out.
       All p-keyed, so the reply re-opens it in mirror on the way back. */
    const presence = seg(p, 0.28, 0.33) * (A.mobile ? 1 - seg(p, 0.72, 0.80) : 1 - seg(p, 0.90, 0.96));
    const open = ease(seg(p, 0.425, 0.46)) * (1 - ease(seg(p, 0.665, 0.705)));
    shellDraw(ctx, A.coreC.x, A.coreC.y, A.shellR, open, presence, t);
    /* EVENT HORIZON — the exposed core is a black hole: the face swallows
       all light, so everything visible lives at the edge — a warm photon
       ring hugging the clip circle, doppler-bright on the approaching side,
       plus a soft accretion halo bleeding outward. p-keyed like the iris. */
    const eh = open * presence;
    if (eh > 0.02) {
      const rr = open * (A.coreR + 4);   // just outside the DOM face edge
      const halo = ctx.createRadialGradient(A.coreC.x, A.coreC.y, rr * 0.8, A.coreC.x, A.coreC.y, rr * 1.4);
      halo.addColorStop(0, 'rgba(0,0,0,0)');
      halo.addColorStop(0.33, `rgba(255,178,102,${0.14 * eh})`);
      halo.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = halo;
      ctx.fillRect(A.coreC.x - rr * 1.5, A.coreC.y - rr * 1.5, rr * 3, rr * 3);
      ctx.beginPath(); ctx.arc(A.coreC.x, A.coreC.y, rr, 0, 6.28);
      ctx.strokeStyle = `rgba(255,214,166,${0.5 * eh})`; ctx.lineWidth = 1.8;
      ctx.shadowColor = 'rgba(255,190,120,.9)'; ctx.shadowBlur = 14; ctx.stroke();
      // doppler beaming: the side spinning toward the viewer burns brighter
      ctx.beginPath(); ctx.arc(A.coreC.x, A.coreC.y, rr, 2.2, 4.35);
      ctx.strokeStyle = `rgba(255,238,214,${0.75 * eh})`; ctx.lineWidth = 2.6;
      ctx.shadowBlur = 22; ctx.stroke(); ctx.shadowBlur = 0;
    }
    /* IN/OUT ports live ON the shell equator — glowing slits + tags; they
       flare while the traveler is scanned through (old slot-scan windows) */
    const portA = presence * ease(seg(p, 0.40, 0.44)) * (1 - ease(seg(p, 0.70, 0.745)));
    if (portA > 0.02) {
      const scanI = seg(p, 0.425, 0.445) * (1 - seg(p, 0.46, 0.48));
      const scanO = seg(p, 0.615, 0.635) * (1 - seg(p, 0.655, 0.675));
      ctx.font = '7px IBM Plex Mono'; ctx.textAlign = 'center';
      for (const [q, lbl, scan] of [[A.intake, 'in', scanI], [A.outlet, 'out', scanO]] as [Pt, string, number][]) {
        const h = 8 + scan * 3;
        ctx.beginPath(); ctx.moveTo(q.x, q.y - h); ctx.lineTo(q.x, q.y + h);
        ctx.strokeStyle = `rgba(143,216,255,${(0.5 + 0.5 * scan) * portA})`;
        ctx.lineWidth = 2 + scan * 1.5;
        ctx.shadowColor = 'rgba(143,216,255,.9)'; ctx.shadowBlur = scan * 14;
        ctx.stroke(); ctx.shadowBlur = 0;
        ctx.fillStyle = `rgba(120,160,190,${0.8 * portA})`;
        ctx.fillText(lbl, q.x, q.y + 22);
      }
      ctx.textAlign = 'left';
    }

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
    // Reverse (desktop): her device does NOT replay its arrival — it stays
    // side-stage while the reply flies back, and only dismisses once the
    // reply is docking on YOUR grown device (owner call, round 15).
    const stayR = dir === -1 && !A.mobile;
    const arrive = stayR ? 1 : ease(seg(p, A.mobile ? 0.72 : 0.62, A.mobile ? 0.82 : 0.76));
    const rpX = lerp(lerp(W * (A.mobile ? 1.35 : 1.15), A.recipC.x, arrive), A.mobile ? W * 0.5 : A.finRx, grow);
    const rpY = lerp(A.recipC.y, H * (A.mobile ? 0.58 : 0.56), grow);
    const rpS = lerp(A.phoneS, A.mobile ? 1 : A.finS, grow);
    const recIn = stayR ? ease(seg(p, 0.03, 0.10)) : ease(seg(p, A.mobile ? 0.70 : 0.60, A.mobile ? 0.80 : 0.74));
    phonePose($('.phone.recipient'), rpX, rpY, rpS, recIn);
    let spX: number, spY: number, spS: number;
    if (A.mobile) {
      const toTop = ease(seg(p, T.lift[0], T.lift[1]));
      const exitL = ease(seg(p, 0.26, 0.36));   // fully out before the capsule crosses its lane
      spX = lerp(lerp(W * 0.5, A.senderC.x, toTop), -W * 0.35, exitL);
      spY = lerp(H * 0.60, A.senderC.y, toTop);
      spS = lerp(1, A.phoneS, toTop);
    } else {
      const moveOut = ease(seg(p, T.lift[0], T.lift[1]));
      // finale: BOTH devices end even — center-stage, as large as fits
      spX = lerp(lerp(W * 0.5, A.senderC.x, moveOut), A.finSx, grow);
      spY = lerp(lerp(H * 0.60, A.senderC.y, moveOut), H * 0.56, grow);
      spS = lerp(lerp(1, A.phoneS, moveOut), A.finS, grow);
    }
    phonePose($('.phone.sender'), spX, spY, spS, 1);

    const sk = $('.keytag.sender-key');
    sk.style.opacity = String(seg(p, 0.14, 0.18) * (1 - seg(p, A.mobile ? 0.25 : 0.30, A.mobile ? 0.29 : 0.36)));
    sk.style.left = `${A.senderC.x - sk.offsetWidth / 2}px`; sk.style.top = `${A.senderC.y + A.keyDy}px`;
    const rk = $('.keytag.recipient-key');
    rk.style.opacity = String(seg(p, 0.84, 0.88) * (1 - seg(p, 0.925, 0.95)));
    rk.style.left = `${A.recipC.x - rk.offsetWidth / 2}px`; rk.style.top = `${A.recipC.y + A.keyDy}px`;

    /* the exposed core — DOM revealed through a clip-circle synced to the
       shell's iris (aperture is slightly wider, so the rim dots always sit
       outside the face); rings are the old rotors, reborn as core machinery */
    $('.machine').style.opacity = String(open);
    $('.core').style.clipPath = `circle(${(open * 50.5).toFixed(2)}% at 50% 50%)`;
    const spin = ease(seg(p, T.swallow[0], T.wire2[0]));
    rotors.forEach((r, i) => { r.style.transform = `rotate(${spin * (360 + i * 220) + t * 8}deg)`; });

    const mine = $('.sv-row.mine');
    const mineO = clamp(Math.min(mineFlowY / 26, (streamH - mineFlowY) / 26), 0, 0.85) * minePres;
    const chM = chord(mineFlowY);
    mine.style.left = `${coreHalf - chM}px`;
    mine.style.width = `${2 * chM}px`;
    mine.style.opacity = String(mineO);
    mine.style.transform = `translate(${(1 - mineIn) * -360 + mineOut * 360}px, ${mineFlowY}px)`;
    /* the tag glides along the sphere's inner wall, pinned to its row's
       curved left edge — hanging out over the shell dots */
    const mineTag = $('.mine-tag');
    const streamR = $('.sv-stream').getBoundingClientRect();
    const machR = $('.machine').getBoundingClientRect();
    mineTag.style.top = `${streamR.top - machR.top + mineFlowY}px`;
    mineTag.style.left = `${streamR.left - machR.left + coreHalf - chM - mineTag.offsetWidth - 6}px`;
    mineTag.style.opacity = String(mineO);

    /* traveler — symmetric two-act structure */
    const tr = $('.traveler');
    let pos: Pt, scale = 1, capsule = false, inside = false;
    // The REAL landing slot: exactly where the next bubble pops in the target
    // thread — one gap below its last child, left-aligned like a them-bubble.
    // getBoundingClientRect folds the phone's live transform in; the traveler
    // footprint is offsetWidth × its final scale (center origin). Fixes the
    // overshoot of the old "phone center + offset" approximation.
    const slotFor = (thread: HTMLElement, s: number): Pt => {
      if (landed && landedBubble && landedBubble.parentElement === thread) {
        const br = landedBubble.getBoundingClientRect();
        return { x: br.left + br.width / 2, y: br.top + br.height / 2 };
      }
      const r = thread.getBoundingClientRect();
      const vs = thread.offsetWidth ? r.width / thread.offsetWidth : 1;
      const last = thread.lastElementChild;
      const yTop = last ? last.getBoundingClientRect().bottom + 7 * vs : r.top + 10 * vs;
      return { x: r.left + 10 * vs + tr.offsetWidth * s / 2, y: yTop + tr.offsetHeight * s / 2 };
    };
    const landSlot = dir === 1 ? slotFor($('.recipient-msgs'), 0.62) : slotFor($('.sender-msgs'), 1);
    if (p < T.lift[1]) {
      const k = ease(seg(p, T.lift[0], T.lift[1]));
      // detach from the REAL bubble in the thread — the copy materializes
      // exactly ON the sent message (tops aligned: the bubble's meta line
      // sits below the text, so center-alignment would offset the twins)
      let start = A.liftStart;
      if (dir === 1 && sentBubble) {
        const br = sentBubble.getBoundingClientRect();
        start = { x: br.left + br.width / 2, y: br.top + tr.offsetHeight / 2 };
      } else if (dir === -1) {
        // the reply's REAL landing slot on YOUR phone
        start = landSlot;
      }
      // reverse: control x at the midpoint → x(t) is LINEAR, so the arrival
      // can never bulge past the slot; the swoop lives in y (forward keeps
      // the wide liftCp swing out of the me-bubble)
      const cp = dir === 1 ? A.liftCp : { x: (start.x + A.sealP.x) / 2, y: A.liftCp.y };
      pos = bez(start, cp, A.sealP, k);
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
      let end = landSlot;
      if (dir === -1 && sentBubble) {
        // reverse: detach from the REAL reply bubble in her thread — twins,
        // exactly like the forward lift
        const br = sentBubble.getBoundingClientRect();
        end = { x: br.left + br.width / 2, y: br.top + tr.offsetHeight / 2 };
      }
      // control x at the midpoint of hold→slot: x(t) is LINEAR — the capsule
      // descends onto the slot without ever swinging past it (the owner's
      // "overshoot"); the drop arc survives in y via dropCp's height
      pos = bez(A.unsealP, { x: (A.unsealP.x + end.x) / 2, y: A.dropCp.y }, end, k);
      scale = lerp(0.9, dir === -1 ? 1 : 0.62, k);
    }

    if (dir === 1) {
      if (p > T.land && !landed) { landed = true; const th = $('.recipient-msgs'); th.appendChild(landedBubble!); trimThread(th); }
      if (p <= T.land && landed) { landed = false; landedBubble!.remove(); }
      if (sentMeta) sentMeta.textContent = p > 0.975 ? '08:12 ✓✓' : '08:12 ✓';
    } else {
      if (p < REV_LAND && !landed) { landed = true; const th = $('.sender-msgs'); th.appendChild(landedBubble!); trimThread(th); }
      if (p >= REV_LAND && landed) { landed = false; landedBubble!.remove(); }
      if (sentMeta) sentMeta.textContent = p < 0.025 ? '08:13 ✓✓' : '08:13 ✓';
    }

    tr.classList.toggle('capsule', capsule);
    tr.style.opacity = String((dir === 1 ? seg(p, 0.015, 0.04) : 1 - seg(p, 0.96, 0.985)) * (landed || inside ? 0 : 1));
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
    ring(ctx, landSlot, dir === 1 ? seg(p, 0.965, 1) : 1 - seg(p, 0.005, 0.05), 34, '255,217,138');

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
    hintEl.style.opacity = sent && (dir === 1 ? p > 0.005 && p < 0.04 : p > 0.955) ? '1' : '0';

    requestAnimationFrame(update);
  }
  update();
}
