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
import { autoGrow, B64, bez, clamp, drawStars, ease, fake, fit, lerp, makeStars, rectC, ring, rnd, seg, type Pt } from './util';
import { drawHorizon, drawPorts, drawSingularity, makeShell } from './shell';

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
  let kbLift: HTMLTextAreaElement | null = null;   // focused composer while the mobile keyboard is up
  let kbSuppressUntil = 0;   // after a dismiss, reject the reflow-induced refocus for a beat

  // While a phone MOVES it needs its own layer (will-change) — but a hint
  // held forever pins the raster made mid-journey at ~0.4× scale, and the
  // docked phone shows that tiny bitmap upscaled: blurry text (owner's
  // "low resolution" placeholder). At rest we release the hint so the
  // browser re-rasters the layer at the TRUE scale — crisp at every dock.
  const poseRest = new WeakMap<HTMLElement, { tf: string; still: number }>();
  const phonePose = (el: HTMLElement, x: number, y: number, s: number, o: number) => {
    const h = el.offsetHeight || 560;
    const tf = `translate(${x - el.offsetWidth / 2 * s}px, ${y - h * s / 2}px) scale(${s})`;
    const st = poseRest.get(el) ?? { tf: '', still: 0 };
    st.still = tf === st.tf ? st.still + 1 : 0;
    st.tf = tf;
    poseRest.set(el, st);
    el.style.willChange = st.still > 20 ? 'auto' : 'transform';
    el.style.transform = tf;
    el.style.transformOrigin = `${el.offsetWidth / 2}px ${h / 2}px`;
    el.style.opacity = String(o);
  };

  // prompt-bottom cache: static block, but gBCR in the per-frame anchors()
  // path would force layout — recompute only when the viewport changes
  let promptBKey = -1, promptBCache = 0;
  function anchors(p: number) {
    // Below 1000px the desktop side-by-side layout crowds (caption text
    // overlaps the relay sphere, docked device covers the wire arc). Owner
    // call: hand narrow/tablet widths to the single-device mobile layout —
    // matches the CSS journey breakpoint (@media max-width:999px).
    const mobile = W < 1000;
    const shortLandscape = mobile && W >= 700 && H <= 650;
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
    // the relay node: sphere geometry from the DOM core box — the dot-shell
    // wraps it, the IN/OUT ports sit on the lower flanks, the wires plug in
    // there. FLIGHT geometry anchors on the FULL-size ports (shellRF); the
    // live shell (shellR) grows/shrinks across the journey.
    const coreEl = $('.core');
    const coreC = rectC(coreEl);
    const coreR = (coreEl.offsetWidth || 300) / 2;
    const shellRF = coreR * 1.16;   // full-size shell — flight geometry
    const phoneSv = mobile ? 0.68 : clamp((railTop - 56 - (H * 0.15 + 270)) / ph, 0.34, 0.58);
    // Devices hug the edges (0.20 / 0.80). But the lower-flank ports are
    // fixed-px (height-scaled), so on a NARROW desktop the %-split lets a
    // docked device crowd its port and the tunnel clips behind it. Push the
    // split OUTWARD symmetrically (about 0.5W → the pair stays even), just far
    // enough to keep 44px between each device's inner edge and its port —
    // clamped so it never slides off-screen; wide desktops keep 0.20/0.80.
    const halfDev = pw * phoneSv / 2;
    const portReach = shellRF * Math.cos(0.62);
    const outFrac = mobile ? 0.5 : clamp(Math.max(0.80, (coreC.x + portReach + 44 + halfDev) / W), 0.80, (W - halfDev - 8) / W);
    const senderC = { x: mobile ? W * 0.5 : W * (1 - outFrac), y: sideY };
    const recipC = { x: mobile ? W * 0.5 : W * outFrac, y: sideY };
    const grow = ease(seg(p, 0.33, 0.425));
    const shrink = mobile ? 0 : ease(seg(p, 0.71, 0.78));
    const shellR = shellRF * (0.55 + 0.45 * grow) * (1 - 0.55 * shrink);
    // Ports sit on the LOWER flanks (~36° below the equator, owner round
    // 27): the tunnel passes UNDER the sphere and enters each port RADIALLY
    // (cp on the center→port ray) instead of skimming tangentially through
    // the dot cloud on its way to an equator port.
    const pdx = Math.cos(0.62), pdy = Math.sin(0.62);
    const intake = { x: coreC.x - shellRF * pdx, y: coreC.y + shellRF * pdy };   // frozen: wires/flight
    const outlet = { x: coreC.x + shellRF * pdx, y: coreC.y + shellRF * pdy };
    const intakeL = { x: coreC.x - shellR * pdx, y: coreC.y + shellR * pdy };    // live: port slits
    const outletL = { x: coreC.x + shellR * pdx, y: coreC.y + shellR * pdy };
    // Both holds SHARE one point, centered UNDER THE NODE. The relay itself
    // sits on the viewport centerline, so its two wire arcs and the symmetric
    // device anchors keep equal left/right spacing. Seal and unseal never
    // coexist, and the shared endpoint fuses the curves into one parabola
    // passing under the sphere. Desktop valley depth is sphere-relative.
    const holdY = mobile ? H * 0.76 : coreC.y + shellRF + 84;
    // REST pose (pre-send / p≈0): on tall screens the composer sits at 0.60H
    // full-size; on SHORT windows (landscape-ish desktop, e.g. 894×530) that
    // put the phone top under the nav, buried the prompt, and pushed the
    // composer row off-screen. restY lifts the scale-free bottom (y + ph/2)
    // back above the viewport edge; restS shrinks the device until its
    // visual top (bottom - ph*s) clears the prompt block.
    const restY = Math.min(H * 0.60, H - 20 - ph / 2);
    // offsetTop-based (relative to the sticky stage), NOT gBCR: a viewport-
    // relative bottom measured while the journey is off-screen poisons the
    // cache with a huge value and shrinks the rest phone to the clamp floor
    if (promptBKey !== W * 100000 + H) {
      promptBKey = W * 100000 + H;
      const pe = $('.prompt');
      promptBCache = pe.offsetTop + pe.offsetHeight;
    }
    const promptB = promptBCache;
    const restS = mobile ? 1 : clamp((restY + ph / 2 - promptB - 10) / ph, 0.45, 1);
    // Desired VISUAL center. phonePose only centers at s=1 (visual center =
    // x + pw*(1-s)/2), so every scaled beat is compensated at the call site
    // (x - pw*(1-s)/2) with the LIVE scale — rest, flight (left/right), and
    // the finale all center truly, with no rightward drift at s<1.
    const restX = W * 0.5;
    const sealP = { x: coreC.x, y: holdY };
    const unsealP = { x: coreC.x, y: holdY };
    return {
      mobile, shortLandscape, senderC, recipC, intake, outlet, intakeL, outletL, sealP, unsealP, coreC, coreR, shellR,
      // Desktop hold scale adapts to the free band between the caption
      // column (~0.15H + 270px) and the rail: on short screens the phone
      // shrinks instead of colliding with caption above or keytag/rail below
      // (visual top = bottom - ph*s, since the visual bottom is scale-free).
      phoneS: phoneSv,
      // Desktop finale: both devices dock center-stage as LARGE as fits —
      // width-limited so they can never collide (centers 0.30W apart, 24px
      // gap), height-limited so the top edge clears the nav. finY pulls the
      // pair UP whenever the base line would drop the scale-free bottom edge
      // (y + ph/2) onto the rail — dots never show through the devices on
      // short viewports; the scale term follows finY, so tops keep clearing
      // the nav (devices trade a little size for a clean dock).
      finY: Math.min(H * (mobile ? 0.58 : 0.56), railTop - 16 - ph / 2),
      finS: mobile ? 1 : clamp(Math.min(
        (W * 0.30 - 24) / pw,
        (Math.min(H * 0.56, railTop - 16 - ph / 2) + ph / 2 - 76) / ph,
      ), 0.55, 1.2),
      finSx: W * 0.35, finRx: W * 0.65,
      restX, restY, restS, pw,
      liftStart: { x: W * 0.5 + (mobile ? 30 : 40), y: restY + (mobile ? 40 : 60) },
      liftCp: mobile ? { x: W * 0.30, y: H * 0.64 } : { x: W * 0.45, y: H * 0.48 },
      dropCp: mobile ? { x: W * 0.66, y: H * 0.58 } : { x: W * 0.66, y: holdY - H * 0.03 },
      // cp x on the center→port ray (near-radial entry, never tangential);
      // cp y averaged with the valley so both arcs leave the shared hold
      // shallowly — a rounded U, not a pointed V (two quadratics meeting at
      // steep tangents kink at the join)
      cp1: { x: coreC.x + (intake.x - coreC.x) * 1.55, y: (coreC.y + (intake.y - coreC.y) * 1.55 + holdY) / 2 },
      cp2: { x: coreC.x + (outlet.x - coreC.x) * 1.55, y: (coreC.y + (outlet.y - coreC.y) * 1.55 + holdY) / 2 },
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
    tag.textContent = "Bob's →";
    $('.machine').appendChild(tag);
  }
  const rotors = [...section.querySelectorAll<HTMLElement>('[data-rotor]')];
  const shellDraw = makeShell();

  /* send — manual (button/Enter) or auto (visitor scrolls past without clicking) */
  const draft = $<HTMLTextAreaElement>('.phone.sender .compose textarea');
  const sendBtn = $<HTMLButtonElement>('.phone.sender .compose button');
  const caret = $('.phone.sender .c-caret');
  const draftR = $<HTMLTextAreaElement>('.phone.recipient .compose textarea');
  const sendBtnR = $<HTMLButtonElement>('.phone.recipient .compose button');
  const caretR = $('.phone.recipient .c-caret');
  const hintEl = $('.journey-hint');
  // keep focus while the ➤ is tapped — a blur here would unfreeze and reflow the
  // phone out from under the finger before the click lands (mousedown-preventDefault
  // is the classic "button that doesn't steal focus"); then send + dismiss keyboard
  sendBtn.addEventListener('mousedown', (e) => e.preventDefault());
  sendBtnR.addEventListener('mousedown', (e) => e.preventDefault());
  sendBtn.addEventListener('click', () => { doSend(false); releaseKb()?.blur(); });
  sendBtnR.addEventListener('click', () => { doSendBack(); releaseKb()?.blur(); });
  // chat-style composers: a long draft WRAPS and the pill grows with it —
  // Enter always sends (swallowed so the textarea never gains a newline);
  // pasted newlines become spaces before anything downstream sees the value
  for (const el of [draft, draftR]) {
    el.addEventListener('keydown', (e) => {
      if (e.key !== 'Enter') return;
      e.preventDefault();
      el === draft ? doSend(false) : doSendBack();
    });
    el.addEventListener('input', () => {
      if (el.value.includes('\n')) el.value = el.value.replace(/\n+/g, ' ');
      autoGrow(el);
      // the growing pill eats thread space — trim so the NEWEST bubbles
      // stay visible, exactly like the send-time stacking rule
      trimThread(el === draft ? $('.sender-msgs') : $('.recipient-msgs'));
    });
    // click/tap a compose → whole draft selected, one keystroke replaces it
    el.addEventListener('focus', () => {
      // after a dismiss, the tap's synthesized click can land on the input as the
      // phone reflows and re-open the keyboard — reject that refocus for a beat
      if (performance.now() < kbSuppressUntil) { el.blur(); return; }
      el.select();
      // mobile: opening the keyboard shrinks the viewport and drifts scroll.
      // Freeze the journey and pin this device above the keyboard (real chat).
      if (innerWidth < 1000) { kbLift = el; document.body.classList.add('kb-open'); }
    });
    el.addEventListener('blur', () => { if (kbLift === el) releaseKb(); });
  }
  // release the keyboard freeze: clear state + drop the fixed lift on both phones
  function releaseKb() {
    kbSuppressUntil = performance.now() + 600;
    const el = kbLift;
    kbLift = null;
    document.body.classList.remove('kb-open');
    $('.phone.sender').classList.remove('kb-lift');
    $('.phone.recipient').classList.remove('kb-lift');
    return el;
  }
  // Done pill AND any tap outside the composer dismiss the keyboard
  const kbDone = document.querySelector<HTMLButtonElement>('.kb-done');
  kbDone?.addEventListener('click', () => releaseKb()?.blur());
  document.addEventListener('pointerdown', (e) => {
    if (!kbLift) return;
    const t = e.target as HTMLElement | null;
    if (t && (t.closest('.compose') || t.closest('.kb-done'))) return;
    releaseKb()?.blur();
  }, true);
  // the sender ships with a prefilled draft — size its pill NOW, and again
  // once the mono font arrives (glyph metrics change the wrap points)
  autoGrow(draft); autoGrow(draftR);
  document.fonts?.ready.then(() => { autoGrow(draft); autoGrow(draftR); });
  // hero "type something private" box and this compose are the SAME draft —
  // last writer wins, whenever the phone is docked
  document.addEventListener('fp:plain', (e) => {
    if (docked()) { draft.value = (e as CustomEvent<string>).detail.slice(0, 120); autoGrow(draft); }
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
    // the giveaway tag names the real sender and points the way this journey
    // flows: forward Bob→Kate (→, left of the row), reply Kate→Bob (←, right)
    $('.mine-tag').textContent = dir === 1 ? "Bob's →" : "← Kate's";
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
    autoGrow(draft);

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

    hintEl.textContent = 'scroll — the message is on its way ↓';
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
    autoGrow(draftR);

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

  /* keyboard lift (mobile): pin the focused device — at FULL size, readable —
     with its composer just above the on-screen keyboard, using visualViewport's
     un-obscured box. The phone goes position:fixed (.kb-lift) so scroll/sticky
     drift can never move it; its top clips off-screen if the band is short,
     exactly like a real chat. Compose-mode CSS hides the surrounding chrome. */
  function poseLifted(el: HTMLTextAreaElement) {
    const phone = $(el === draft ? '.phone.sender' : '.phone.recipient');
    phone.classList.add('kb-lift');
    const other = $(el === draft ? '.phone.recipient' : '.phone.sender');
    other.classList.remove('kb-lift');
    other.style.opacity = '0';
    const vv = window.visualViewport;
    const vTop = vv ? vv.offsetTop : 0;
    const vH = vv ? vv.height : H;
    const ph = phone.offsetHeight || 560;
    phonePose(phone, W / 2, vTop + vH - 6 - ph / 2, 1, 1);
    if (kbDone) kbDone.style.top = `${vTop + 14}px`;
  }
  function update() {
    const now = performance.now(), t = now / 1000;
    // self-heal on any viewport change the resize event missed (devtools
    // device-toolbar toggles can land before layout settles)
    if (canvas.clientWidth !== W || canvas.clientHeight !== H) {
      ctx = fit(canvas); W = canvas.clientWidth; H = canvas.clientHeight; stars = makeStars(W, H, 240);
    }
    // keyboard freeze (mobile): a focused composer holds the journey still and
    // lifts its device above the keyboard; nothing else recomputes meanwhile
    if (kbLift) { poseLifted(kbLift); requestAnimationFrame(update); return; }
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
        autoGrow(draft);
        document.dispatchEvent(new CustomEvent('fp:clear'));
      }
      if (document.activeElement !== draftR) { draftR.value = ''; autoGrow(draftR); }
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
    // chord-fit a row into the sphere at its height (ambient AND mine rows
    // must place identically — lockstep by construction, not by copy)
    const fitRow = (el: HTMLElement, yTop: number) => {
      const ch = chord(yTop);
      el.style.left = `${coreHalf - ch}px`;
      el.style.width = `${2 * ch}px`;
      return ch;
    };
    // layout reads batched HERE, before any style write this frame — the
    // mine-tag placement below must not force a second synchronous reflow
    const mine = $('.sv-row.mine');
    const mineTag = $('.mine-tag');
    const tagW = mineTag.offsetWidth;
    const streamR = streamEl.getBoundingClientRect();
    const machR = $('.machine').getBoundingClientRect();
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
      fitRow(r.el, y);
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
      phonePose($('.phone.sender'), A.restX - A.pw * (1 - A.restS) / 2, A.restY, A.restS, 1);
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
    const q = A.mobile ? 0.6 : 1;   // mobile: cheaper glow (blur only — never dots)
    /* the CONTAINED singularity: while the shell is closed (approach, and
       the desktop sealed-mini afterwards) the small unstable black hole is
       visible through the lattice — drawn UNDER the dots, so the shell
       cages it; it hands off to the full horizon exactly as the iris opens */
    drawSingularity(ctx, A.coreC.x, A.coreC.y, A.shellR * 0.34, presence * (1 - open), t, q);
    shellDraw(ctx, A.coreC.x, A.coreC.y, A.shellR, open, presence, t);
    // event horizon at the clip edge (rr just outside the DOM face)
    drawHorizon(ctx, A.coreC.x, A.coreC.y, open * (A.coreR + 4), open * presence, q);
    /* IN/OUT ports ride the LIVE shell's lower flanks; they flare while
       the traveler is scanned through (the old slot-scan windows) */
    const portA = presence * ease(seg(p, 0.40, 0.44)) * (1 - ease(seg(p, 0.70, 0.745)));
    drawPorts(ctx, A.intakeL, A.outletL, portA,
      seg(p, 0.425, 0.445) * (1 - seg(p, 0.46, 0.48)),
      seg(p, 0.615, 0.635) * (1 - seg(p, 0.655, 0.675)), q, 0.62);

    /* the TLS TUNNELS, mirrored — the caption says "ciphertext, inside TLS",
       so the wire is drawn as a tunnel of light, not a dashed diagram line:
       three layered strokes (halo → sheath → core) that brighten toward the
       node (light bending into the well) with a slow ambient shimmer, plus a
       few photons drifting the way the traffic actually flows (into the node
       on the IN rail, out of it on the OUT rail). Geometry is unchanged from
       the dashed version: FROZEN flight curves (the capsule never leaves its
       rail) clipped at the LIVE shell body, so the tunnel always plugs into
       the node's surface wherever it is now. Photons/shimmer are ambient
       time (stars class); the tube itself stays a pure function of scroll. */
    // while the message rides INSIDE the node, the wire act rests: the
    // tunnel dims to a trace so the open black hole owns the stage (owner
    // round 27), and re-lights for the emit
    const insideDip = seg(p, 0.475, 0.51) * (1 - seg(p, 0.585, 0.615));
    const pathAlpha = seg(p, 0.22, 0.30) * (1 - seg(p, 0.95, 1)) * (1 - 0.85 * insideDip);
    if (pathAlpha > 0) {
      const rimR = A.shellR + 2;
      const rails = [
        [A.sealP, A.cp1, A.intake, 1],    // sphere at k=1 → flow: device → node
        [A.outlet, A.cp2, A.unsealP, 0],  // sphere at k=0 → flow: node → device
      ] as [Pt, Pt, Pt, number][];
      ctx.lineCap = 'round';
      for (let ri = 0; ri < rails.length; ri++) {
        const [P1, CP, P2, sEnd] = rails[ri];
        // contiguous visible runs (rim-clipped), each stroked ONCE per layer —
        // per-segment strokes would double-alpha at every round-cap joint and
        // bead the rail like the old dashes
        const runs: { pts: Pt[]; u0: number; u1: number }[] = [];
        let cur: Pt[] = [], u0 = 0;
        for (let k = 0; k <= 40; k++) {
          const pt = bez(P1, CP, P2, k / 40);
          if (Math.hypot(pt.x - A.coreC.x, pt.y - A.coreC.y) < rimR) {
            if (cur.length > 1) runs.push({ pts: cur, u0, u1: (k - 1) / 40 });
            cur = [];
          } else {
            if (!cur.length) u0 = k / 40;
            cur.push(pt);
          }
        }
        if (cur.length > 1) runs.push({ pts: cur, u0, u1: 1 });
        const breath = 1 + 0.08 * Math.sin(t * 1.6 + ri * 3);   // whole-rail life, no beads
        for (const run of runs) {
          const first = run.pts[0], last = run.pts[run.pts.length - 1];
          const glA = (0.65 + 0.35 * (sEnd ? run.u0 : 1 - run.u0)) * pathAlpha * breath;
          const glB = (0.65 + 0.35 * (sEnd ? run.u1 : 1 - run.u1)) * pathAlpha * breath;
          for (const [w, al] of [[10, 0.05], [4, 0.12], [1.4, 0.42]] as const) {
            const lg = ctx.createLinearGradient(first.x, first.y, last.x, last.y);
            lg.addColorStop(0, `rgba(143,216,255,${al * glA})`);
            lg.addColorStop(1, `rgba(143,216,255,${al * glB})`);
            ctx.beginPath();
            run.pts.forEach((q2, i) => i === 0 ? ctx.moveTo(q2.x, q2.y) : ctx.lineTo(q2.x, q2.y));
            ctx.lineWidth = w; ctx.strokeStyle = lg;
            ctx.stroke();
          }
        }
        // photons drift the way the CURRENT journey flows: forward =
        // device→node on IN and node→device on OUT (ascending k); a reply
        // reverses both — the tunnel never visibly opposes its capsule
        for (let i = 0; i < 3; i++) {
          const u0p = (t * 0.10 + i / 3 + ri * 0.17) % 1;
          const u = dir === 1 ? u0p : 1 - u0p;
          const pt = bez(P1, CP, P2, u);
          if (Math.hypot(pt.x - A.coreC.x, pt.y - A.coreC.y) < rimR) continue;
          const fade = Math.sin(u * Math.PI);   // born/absorbed softly at the ends
          const g2 = ctx.createRadialGradient(pt.x, pt.y, 0.5, pt.x, pt.y, 7);
          g2.addColorStop(0, `rgba(190,232,255,${0.55 * fade * pathAlpha})`);
          g2.addColorStop(1, 'rgba(143,216,255,0)');
          ctx.beginPath(); ctx.arc(pt.x, pt.y, 7, 0, 6.28);
          ctx.fillStyle = g2; ctx.fill();
        }
      }
      ctx.lineCap = 'butt';
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
    const rpY = lerp(A.recipC.y, A.finY, grow);
    const rpS = lerp(A.phoneS, A.mobile ? 1 : A.finS, grow);
    const recIn = stayR ? ease(seg(p, 0.03, 0.10)) : ease(seg(p, A.mobile ? 0.70 : 0.60, A.mobile ? 0.80 : 0.74));
    phonePose($('.phone.recipient'), rpX - A.pw * (1 - rpS) / 2, rpY, rpS, recIn);
    let spX: number, spY: number, spS: number;
    if (A.mobile) {
      const toTop = ease(seg(p, T.lift[0], T.lift[1]));
      const exitL = ease(seg(p, 0.26, 0.36));   // fully out before the capsule crosses its lane
      spX = lerp(lerp(A.restX, A.senderC.x, toTop), A.shortLandscape ? W * 1.35 : -W * 0.35, exitL);
      spY = lerp(A.restY, A.senderC.y, toTop);
      spS = lerp(A.restS, A.phoneS, toTop);
    } else {
      const moveOut = ease(seg(p, T.lift[0], T.lift[1]));
      // finale: BOTH devices end even — center-stage, as large as fits
      spX = lerp(lerp(A.restX, A.senderC.x, moveOut), A.finSx, grow);
      spY = lerp(lerp(A.restY, A.senderC.y, moveOut), A.finY, grow);
      spS = lerp(lerp(A.restS, A.phoneS, moveOut), A.finS, grow);
    }
    phonePose($('.phone.sender'), spX - A.pw * (1 - spS) / 2, spY, spS, 1);

    const sk = $('.keytag.sender-key');
    sk.style.opacity = String(seg(p, 0.14, 0.18) * (1 - seg(p, A.mobile ? 0.25 : 0.30, A.mobile ? 0.29 : 0.36)));
    const rk = $('.keytag.recipient-key');
    rk.style.opacity = String(seg(p, 0.84, 0.88) * (1 - seg(p, 0.925, 0.95)));

    /* the exposed core — DOM revealed through a clip-circle synced to the
       shell's iris (aperture is slightly wider, so the rim dots always sit
       outside the face); rings are the old rotors, reborn as core machinery */
    $('.machine').style.opacity = String(open);
    $('.core').style.clipPath = `circle(${(open * 50.5).toFixed(2)}% at 50% 50%)`;
    const spin = ease(seg(p, T.swallow[0], T.wire2[0]));
    rotors.forEach((r, i) => { r.style.transform = `rotate(${spin * (360 + i * 220) + t * 8}deg)`; });

    const mineO = clamp(Math.min(mineFlowY / 26, (streamH - mineFlowY) / 26), 0, 0.85) * minePres;
    const chM = fitRow(mine, mineFlowY);
    mine.style.opacity = String(mineO);
    // forward slides in through the left (IN) port; a reply enters from Kate's
    // right (OUT) port — mirror the horizontal glide so it never opposes travel
    const mineSlide = dir === 1 ? 1 : -1;
    mine.style.transform = `translate(${((1 - mineIn) * -360 + mineOut * 360) * mineSlide}px, ${mineFlowY}px)`;
    /* the tag glides along the sphere's inner wall, pinned to its row's curved
       edge (left on the way out, right on a reply) — out over the shell dots
       (rects and tag width were read up top, before this frame's first write) */
    mineTag.style.top = `${streamR.top - machR.top + mineFlowY}px`;
    mineTag.style.left = `${streamR.left - machR.left + coreHalf + (dir === 1 ? -chM - tagW - 6 : chM + 6)}px`;
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

    // Keytags hug their flank device on desktop (the traveler holds dead-centre,
    // far from either edge). In mobile every actor is centred, so a label parked
    // under the device lands on the capsule holding mid-screen — shove it just
    // below the LIVE capsule, but ONLY when they'd actually overlap (tall screens
    // keep the tag hugging the device). Arrival-gated → smooth on scrub AND
    // reverse; geometry is same-frame (pos/scale), never a guessed hold point.
    const capTop = pos.y - tr.offsetHeight * scale / 2;
    const capBot = pos.y + tr.offsetHeight * scale / 2;
    const skTop = A.senderC.y + A.keyDy;
    const skHit = A.mobile && skTop < capBot - 4 && skTop + sk.offsetHeight > capTop + 4;
    sk.style.left = `${A.senderC.x - sk.offsetWidth / 2}px`;
    sk.style.top = `${skTop + (skHit ? Math.max(0, capBot + 12 - skTop) * ease(seg(p, 0.08, 0.14)) : 0)}px`;
    const rkTop = A.recipC.y + A.keyDy;
    const rkHit = A.mobile && rkTop < capBot - 4 && rkTop + rk.offsetHeight > capTop + 4;
    rk.style.left = `${A.recipC.x - rk.offsetWidth / 2}px`;
    rk.style.top = `${rkTop + (rkHit ? Math.max(0, capBot + 12 - rkTop) * ease(seg(p, 0.78, 0.84)) : 0)}px`;

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
