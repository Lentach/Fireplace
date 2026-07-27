# Landing page brainstorm + prototypes (4 rounds: fire → space → full page → message journey)

**Date:** 2026-07-16

## What was done

Owner asked to brainstorm a top-tier marketing/landing page representing the final
product. Session produced decisions + three rounds of throwaway prototypes.

Decisions (owner-confirmed via interactive ask):
1. **Routing**: PWA stays at `/`; landing goes to `/welcome` (or a subdomain).
   Explicitly rejected moving the app path — installed-PWA scope changes risk
   service-worker breakage and the local E2E Signal keys make any "reinstall to fix"
   path unacceptable.
2. **Stack direction** (for the real page, not yet built): separate static site —
   Astro + GSAP ScrollTrigger + Lenis + raw GLSL/canvas. NOT Flutter web (1.5MB+
   first paint, no SEO). Deploys as plain files via the existing nginx atomic-swap
   pattern.
3. **Scope**: prototype-first to validate aesthetics before building anything real.

### Round 1 — FIRE (`docs/design/landing-prototype/index.html`) — theme DROPPED

3 variants (Inferno Hero / Ash Minimal / Warm Hearth Editorial) around a GLSL fbm
fire shader + ember particles + "burn-to-ciphertext" demo (typing re-encrypts a
fake `3:base64…` line — real PreKey wire prefix from CLAUDE.md §7 — with staggered
scramble animation). Owner flipped all 3 and dropped the fire theme.

### Round 2 — SPACE (`docs/design/landing-prototype/round2-space/index.html`) — B WON

Owner reference: fin.com via land-book 97118 ("space, planets, black, visible
connection links around the planet"). Dissected the reference in-browser:
planet-horizon composition, thin glowing arcs, quiet serif, mono stat ledger,
huge black negative space. Built 3 variants, same single-file switcher skeleton:
- **A — Planet Horizon** (fin-faithful): warm-gold planet limb rising from the
  bottom, arc pulses, Cormorant Garamond serif, stat rule. Gold deliberately
  bridges the ember brand into space.
- **B — Dot Globe** ★ WINNER: rotating 3D fibonacci dot-sphere with 3D bezier
  arcs riding the rotation, Archivo-caps brutalist split layout, ice-blue.
- **C — Constellation**: nodes are named *people*, message pulses travel the
  links, Spectral extralight + violet.
Encrypt demo carried over unchanged (owner only rejected the fire skin).

**Round 2 verdict: owner picked B ("the blue dot planet") and asked for rotate +
scope.** Implemented interactivity on B: pointer-drag rotates (horizontal → spin
with inertia, auto-spin resumes when idle; vertical → tilt ±1.2 rad), wheel zooms
0.55–2.3× with dot/arc sizes scaling by `zoom^0.7` so the sphere doesn't dissolve
when scoped in; pulsing hint label until first interaction; drag/wheel hit-tested
to the globe's screen radius so input/CTA/switcher stay usable; per-variant
listeners scoped via `AbortController` re-created in `render()`.

### Round 3 — FULL PAGE (`docs/design/landing-prototype/round3-fullpage/index.html`) — flow validated

Owner shared competitor refs (zangi.com, wire.com, getsession.org) — judged "mid,
we can do a lot better". Critique captured in chat: steal Zangi's annotation
callouts, Session's copy discipline, Wire's dark→light rhythm; ban stock photos
and fake trust signals. Built a single full-page scroll skeleton (no variants —
question is FLOW): globe hero (drag rotate + **Ctrl+scroll** zoom so plain scroll
scrolls the page; headline "Messages only two people can read." + encrypt demo)
→ dark→light bridge → product reveal ("You see the conversation. We see noise.":
stylized phone w/ Polish chat + 3 annotation callouts + live "what the server
stores" ciphertext log ticker) → feature trio (Sealed/Yours/Ephemeral, claims
true per CLAUDE.md §6/§7) → honest ledger strip → dark starfield outro ("Talk
like no one's listening.") + footer. IntersectionObserver staggered reveals.
**Honesty pass**: "open source" downgraded to "public source" — repo is public
but has NO LICENSE file (verified by glob); features card wording "code is
public" kept. No download counts, no testimonials anywhere.
Owner explicitly confirmed the "what the server stores" segment as a keeper.

### Round 4 — MESSAGE JOURNEY (`docs/design/landing-prototype/round4-journey/index.html`) — **WINNER** ("crying rn its great")

Owner overnight idea: interactive journey following one message from the Send
click to delivery, server as one stop. Built: page opens LOCKED (body overflow
hidden) on a live conversation window; pressing ➤ (or Enter) drops the draft
into the chat, builds the traveler bubble (plaintext spans + hidden cipher-growth
spans), unlocks scrolling; scroll drives an 800vh sticky stage via rAF:
lift-off → per-char seal scramble to `3:…` (key tag "never leaves this device")
→ capsule rides dashed bezier arc (TLS) → docks at server panel where the stored
row TYPES ITSELF (`"encryptedContent"`, `"messageType"`, `"deliveryStatus"`,
`"createdAt"` — real quoted-camelCase columns) → second arc, recipient phone
slides in → chars unscramble, lands in her chat "✓✓ delivered" (her key tag) →
end card "That's the whole story. We're just the courier." + replay. Journey
rail (5 stops) lights with progress. Verified headless: locked gate blocks
wheel pre-send; send unlocks; screenshots at seal/server/unseal/end all correct;
0 console errors. Fixed during verification: caption overlap with sender phone
(captions moved bottom-left → top-left), one mis-anchored edit that briefly put
CSS text into the body (repaired same turn; advisory raced behind the fix).
Harness-only scroll race when chaining programmatic scrolls — settled via
scroll-stability polling; not a real UX bug.

**Iteration 2 (owner: "better transitions device→server; bring back the flowing
encrypted-messages animation; message must land and appear on screen"):** capsule
launches from the sent bubble via bezier lift + glow trail; server stop shows a
continuous bottom→top stream of dim ciphertext rows with YOUR row docking in
highlighted+opaque ("yours → 08:12:03 3:…", dims after relay); impact rings at
server dock / phone arrival / gold on-screen landing; REAL landing — traveler
vanishes at p>.955 and the message appends inside her chat (pop-in), sender
meta ✓→✓✓; all reversible on scroll-back (asserted: landed flag, her-chat DOM,
ticks revert at p=0.80). Verified headless: stream stage, mid-unseal, landing —
all correct, 0 console errors; fixed translucent mine-row bleed-through
(opaque #13202e).

**Iteration 3 (owner: server should be an "enigma machine" — message scanned in
one side, encrypted stream in the middle, spat out the other side):** server stop
rebuilt as the RELAY MACHINE ("fireplace relay nº1"): 3 spinning rotor dials
(scroll-driven + idle drift), IN/OUT slit slots with scan-line flashes and impact
rings, ciphertext stream as the machine's window, stamp "routes everything ·
reads nothing". Capsule: wire1 → intake scan → swallowed (scale→0) → hidden while
its row docks in the window → emitted from OUT slit → wire2. Honesty guard kept
explicit: unlike a real Enigma the machine transforms nothing — caption "In
sealed. Out sealed.", identical ciphertext in and out. Verified headless:
swallow/process/emit asserted (traveler opacity 0 + mineRow 1 inside; re-emitted
at p=.72), landing + ✓✓ intact, 0 console errors.

### PRODUCTION BUILD — `landing/` on branch `feat/landing-page` (pushed, `f041732`)

Owner green-lit ("you have a clear path start"). Built the real `/welcome` site:
**Astro static + Lenis** (deliberate deviation: NO GSAP — the validated custom
scroll-progress engine ports as-is; rewriting it as ScrollTrigger timelines is
regression risk for zero visual gain). 31 kB JS total (10.5 kB gzip).
Composition: nav (scroll-aware dark→light flip) → globe hero + encrypt demo →
MESSAGE JOURNEY (spine; send is interactive, **auto-sends when a visitor just
scrolls past** — no body scroll-lock mid-page) → light zone (feature trio +
honest ledger) → starfield outro → footer. Modules:
`src/scripts/{util,globe,encrypt,journey,main}.ts`, `src/styles/landing.css`,
`src/pages/index.astro`. Ctrl+scroll globe zoom coexists with Lenis (Lenis
ignores ctrl+wheel). `base: '/welcome'`.

Ship kit: `landing/deploy-landing.ps1` (npm ci + build → scp staging → guarded
atomic swap into `~/fireplace/landing-build/` → curl verify) + `landing/README.md`
with the ONE-TIME nginx block (plain `alias` + `index`; deliberately NO
`try_files` — alias+try_files is an nginx footgun and a static page needs no
SPA fallback). Branch created via new worktree `../fireplace-landing` off
origin/master (this worktree carries owner's PR #84 WIP). `graphify update`
ran in the landing worktree (graphify-out is gitignored).

**Owner local review iteration (`3cd3626`):** owner tested on localhost (preview
server `landing-preview`, persist, also on LAN 192.168.1.69:4321 — binding
curl-verified 200). Three fixes from the review: (1) wire-1 rerouted — capsule
approaches the IN slit from below via `cp1 = intake.x-90, H*0.52` (was crossing
the caption text); machine shifted `left:55%, 620px`, captions `max-width:300px`
(they physically overlapped at ≤1440w before). (2) Your row now slides INTO the
machine window through the IN side (translateX -340→0), sits between the other
ciphertext rows, then slides OUT (+360) and VANISHES as the capsule re-emerges —
owner's "enters between the encrypted text, disappears when it moves on".
(3) New held decryption stage: capsule reaches `holdP (60%W,55%H)`, grows to
0.95 scale, unscrambles char-by-char over p .80–.93 (openAt .82+.09·rand), THEN
shrinks into her chat (land at .968) — owner: the decrypt moment was "too small
too fast". All still pure p-functions; reverse-scroll re-asserted (un-lands,
row re-docks). Stray `scripts/landing.css` from a bad cp was committed then
amended out (force-with-lease, own branch).

**Owner review round 2 (`150e93b`, owner AFK — autonomous screenshot loop):**
owner: machine→receiver route worse than before, decrypt focus bad ("must be
even on both sides… decrypt effect must be same as encrypt"), relay row looked
layered over the stream instead of joining it, mobile bad. Fixes:
(1) **Symmetric timeline** (`T` map in journey.ts): lift .02–.15 / seal hold
.15–.28 / wire1 .28–.47 ↔ emit .585–.63 / wire2 .63–.82 / unseal hold .82–.945
/ drop .945–.972 — equal leg durations, both holds at scale 0.9, decrypt uses
the same staggered mechanics as encrypt (openAt .83+.10·rand mirrors sealAt);
cp2 = mirror of cp1 (outlet+90, H*.52); drop bezier mirrors the lift.
(2) **Relay row blends**: same metrics as stream rows (no box/glow/size bump),
slides in at window bottom, drifts UP with the flow (p-driven), fades as the
capsule re-emerges; solid panel-color bg so passing time-driven rows occlude
cleanly instead of text-colliding.
(3) **Mobile <700px**: JS anchors branch (phones bottom 82%H scale .5, holds at
66%H, machine rect-anchored) + CSS media query (captions top-center 9.5% clear
of nav, machine 94vw @42%, compressed rail, `.lbl-tail` hidden). Verified by
screenshot sweep at 1401×813 AND 390×844: seal/machine/unseal/land + forward
and reverse assertions both viewports, 0 console errors.

**Owner review round 3 (`372af6c`):** owner mobile screenshots: hero form had a
left gap and overflowed right (content padding was `6vw` left-only → now
symmetric), and journey phones were "miniatures at the bottom" — reworked
mobile choreography: **phones are protagonists** — sender phone TOP-CENTER at
0.68 scale through the seal, exits left as wire1 takes over; machine fades
.68–.76 after relaying; recipient phone slides in TOP-CENTER for the finale
and the decrypted message rises INTO its chat (landPt 42%H). Holds at 76%H
under the large phone; key tags badge onto the phones. Desktop paths untouched
(explicit mobile/desktop branch in pose code). Verified 390×844 hero/seal/
finale/landing + assertions; desktop regression-checked; 0 errors.

**Owner review round 4 (`4963179` + `4efb2af`):** mobile-sweep fix (sender phone
exits before capsule crosses) then a 6-item punch list: (1) finale phone now
GROWS to full size as the message lands, both platforms — journey ends the way
it began; landing point tracks the growing phone (dynamic landPt from the
recipient pose). (2) recipient key tag under the device, fades pre-growth;
keyDy clamped `min(190, H*0.23)` for short desktop viewports (rail collision).
(3) machine stream rows had random speeds → lapping/overlap; now uniform speed
+ even index-spacing (7 mobile / 9 desktop) — collisions impossible.
(4) stars were generated once and never redistributed → after any window
resize they clustered left; all three canvases (journey/globe/outro) now
regenerate stars on resize. (5) wire curves rebuilt as mirrored single-bend
quadratics (cp = chord midpoint at hold height) — clean and symmetric by
construction. (6) prompt/caption-01 overlap during handoff — prompt fades by
.035, cap01 starts .045. Verified 390×844 + 1568×721 incl. the resize path.

**Owner review round 5 (`0ba1330`):** new mobile screenshots. (1) key tags
covered the devices — root cause: `phonePose` uses a center transform-origin
with translate compensation, so the phone's visual bottom is `y + h/2`
REGARDLESS of scale; mobile `keyDy` is now `offsetHeight/2 + 16` (dynamic),
desktop keeps the `min(190, H*0.23)` clamp (721px viewports have zero room
between phone bottom 692 and rail 660). Tags also self-center via
`offsetWidth/2`. (2) relay "mine" row fully blends with the queue — same
`#4c6478` color, padded with `fake()` to the ambient 40-char length; the only
giveaway is a new `.mine-tag` ("yours →", yellow) appended to `.machine`,
pinned at `left:-4px` OUTSIDE the clipped stream (over the IN slot) and
synced to the row's y/opacity each frame via rect diff. (3) row exit now
mirrors entry: slides out LEFT (−360, owner-specified direction) with the
same easing instead of the old +40px fade. (4) hero "type something private"
input dispatches `fp:plain`; journey pre-fills the sender draft until the
visitor types there directly (`draftTouched`) or sends — typed hero text
becomes the journey message. Verified 390×844 + 1568×721: gaps 16px, tag/row
aligned to 0.01px, land/reverse intact, hero→draft sync live.
Follow-up (`ce405cf`, owner-quizzed via ask): (5) machine rows now do a FULL
hero-style re-scramble loop — each row refreshes every 2.5–8.5s with a fresh
timestamp + staggered `settleAt` scramble (per-char spans, `.sv-row .hot`
glow). Honesty framing: the timestamp refresh means "a NEW envelope took the
slot", not "the machine rewrote a message"; the visitor's own row stays
FROZEN (owner's pick) — churn all around, yours untouched. (6) exit direction
flipped RIGHT toward the OUT slit (owner's pick over the literal-left first
cut), feeding the capsule re-emergence. Verified both viewports (hotMax
70–114 chars, 7/9 rows refreshed in 6s, mine frozen). Gotcha: background
browser tabs throttle rAF — `page.bringToFront()` before assertions.

**Owner review round 6 (`d79ec2e`):** (1) mine row is now a REAL queue member —
at entry it takes over whichever ambient slot sits nearest `streamH*0.72`
(lower-visible zone, so the arrival is always seen); that row fades, mine
adopts its exact flow phase (`rowY(idx)`), climbs at STREAM_SP with identical
edge-fade/wrap, verified 14.06 px/s == ambient. Fixed-slot first cut failed:
slot could be outside the visible band → invisible act. State `mineSlot`
resets when presence hits 0 (reverse-scroll safe). (2) exit re-timed to the
entry mirror: row out [.555,.60] fully gone before capsule emit [.585,.63]
(was [.60,.645] — row lingered after emergence, owner flagged). (3) desktop
keytag: root cause was NO under-space — at 1225×1134 the phone bottom sat 8px
above the rail. Fix at source: desktop `sideY = min(0.66H, railTop-ph/2-56)`
(rail-aware raise) + adaptive hold scale `phoneS = clamp((railTop-56-(0.15H+270))/ph,
0.34,0.58)` so short screens (721) shrink the phone instead of colliding with
caption-02 above or tag/rail below; keytag unconditionally `ph/2+16` under the
device. Verified 1225×1134 / 1568×721 / 1401×813 / 390×844: phone→tag 16px,
tag→rail 14px, cap→phone 13px everywhere; full flow (seal/machine/unseal/land)
coherent at shrunken scale; finale growth unaffected (grow targets 0.95/1.0,
not phoneS). (4) hero↔compose draft now last-writer-wins (dropped the
`draftTouched` gate); compose proven interactive via real click+keyboard
(typed "hello kasia", Enter → sent bubble). Caveat discovered: clicking the
compose from hero scroll-position auto-sends first (scrollIntoView crosses
raw>0.015) — designed skimmer behavior, not a bug.

**Owner review round 7 (`57f3da2`):** owner confirmed rounds worked (his "still
broken" was a stale tab — remind him to hard-refresh / use the LAN URL
`192.168.1.69:4321/welcome`). (1) Typing zone: auto-send threshold 0.015 →
0.06 (~90px → ~350px of scroll) so the visitor can stop at the journey top
and edit the compose; the hair-trigger was why he "couldn't delete" the draft
(it had already sent + locked). Compose focus → `select()` so one keystroke
replaces the default. Three message paths all live: hero input / compose edit
/ default "meet me at eight". (2) No auto-send pop: p now normalizes over the
post-send remainder — `raw0 = min(rawAtSend, 0.06)` captured in `doSend`,
`p = (raw−raw0)/(1−raw0)` — journey always starts at 0 from the send point
(manual top-send: raw0=0). `__journey.raw0` exposed; test helpers must map
`raw = raw0 + p·(1−raw0)`. (3) Machine act DOUBLED (owner: "2 scrolls and
it's gone… showcase it"): full timeline re-cut, T now lift .02–.14 /
sealHold .14–.26 / wire1 .26–.39 / swallow .39–.435 / inside .435–.655 /
emit .655–.70 / wire2 .70–.83 / unsealHold .83–.95 / drop .95–.972 — relay
act .39–.70 = 31% of track (~1800px scroll, was 16%), symmetry invariants
kept (wire1==wire2, holds equal, swallow==emit). ALL dependent constants
remapped: mine in/out [.42,.465]/[.625,.67], scans, rings, machine fade
[.32,.38]/(mob [.71,.79]), keytags, sender exit [.26,.36], sealAt/openAt
.15+.09r/.84+.09r, caps data-a/b + rail data-p in index.astro. Verified
390×844 + 1568×721: editable at raw .04, p=.005 just past threshold, mine
rides .42–.67, land/reverse OK. Gotcha again: background tabs freeze
mid-transition styles (phantom prompt overlay in screenshots) —
`bringToFront()` before capture.

**Owner review round 8 (`53cc5b4`):** (1) relay act trimmed 25% (owner: "a bit
too slow now") — T re-cut: wire1/wire2 .26–.43/.66–.83 (.17 each), swallow
.43–.475, inside .475–.615, emit .615–.66; act = 23% of track; holds/sealAt/
openAt/keytags untouched; all dependents remapped (mine [.46,.505]/[.585,.63],
scans, rings, machine fade [.36,.42]/mob-out [.67,.75], traveler shrink/grow
(.26,.38)/(.71,.83), caps [.28,.42]/[.44,.64]/[.67,.81], rail .43/.66).
(2) Chat-realism: compose CLEARS on send (message lives only in the thread),
placeholder "Message…" added; owner's image2 (app compose with emoji/mic
icons) noted but deprioritized — behavior matched, visual sheet copy NOT done.
(3) mine machine row now clamped AND padded to exactly 40 chars — long custom
messages no longer overflow past ambient rows. (4) REVERSE-RESET: journey is
replayable — scroll back to the journey top (raw ≤ .02, gated maxP > .05) →
send undoes (sent bubble + landed bubble removed, compose unlocks EMPTY per
advisory, traveler cleared); hero feeds again; re-send works. BUG CAUGHT in
first cut: reset gate (raw0+.002=.062) sat ABOVE the send gate (.06) →
send/reset oscillation every frame in the overlap band (flickering bubbles,
un-clickable button). Fix: reset only at absolute top (raw ≤ .02) — 4%-of-
track hysteresis. Verified 390×844: send default → land → return → sent=false
/ 2 base bubbles / empty compose → typed "second try" → sent + landed.
Harness note: direct scrollTop sets race Lenis's own target — poll scrollY
until 4 stable samples before clicking page UI.

**Owner review round 9 (`cdfdeb4`, final touches):** (1) compose bars now
mirror the app on BOTH phones: ☺ icon + rounded "Type a message…" field +
➤ send (sender) / 🎙 mic (recipient); `.c-ic` styles in landing.css.
(2) Reset moved from absolute top to THE DEVICE: `raw ≤ raw0` (owner: "when
i reverse to the kasia device let me type") — gates share the .06 boundary
but can't oscillate: reset needs maxP > .05 and resetSend zeroes maxP, so a
boundary-jitter re-send self-damps in one cycle. (3) Empty-draft send falls
back to the PREVIOUS `plain` (replay-by-scrolling resends your message, never
a surprise default). (4) Advisory-driven: auto-send NEVER fires while the
compose is focused — after a device-reset the visitor sits ON the boundary
and mobile keyboard/scroll drift must not fire a half-typed message; blur +
scroll = replay. Verified 390×844: reverse-to-device unlocks empty compose →
"new one" sent from raw0=.0499; no-typing replay resends previous; focused
typing at raw .08 does NOT send, blur → sends typed text. Known edge: focus →
scroll deep → blur pops the traveler mid-wire (raw0 clamped .06) — rare,
accepted.

**Owner review round 10 (`aa1b257`):** (1) lower panel now mirrors the CURRENT
app 1:1 (owner screenshot): rounded pill = chevron-up + "Type a message…" +
mic (recipient) / circular ➤ outside (sender), plus a second tool pill with
six inline stroke-SVG icons (trash-x, hourglass+dot, burst, paperclip, GIF
badge, flask) — decorative showcase, `.c-pill`/`.c-tools`/`.c-row` in
landing.css; ☺ emote removed (owner: being removed from app). (2) threads
STACK like a real chat: resetSend keeps sentBubble; oldest bubble drops past
5. Advisory-caught dupe-spam fixed: `isNew = typed !== '' && typed !== plain`
— a textless replay RE-ANIMATES the existing bubble (sentMeta re-pointed via
querySelector), only new text appends. (3) reset gate widened: fires on
`raw <= raw0 && (maxP > .05 || raw < raw0 - .02)` — send-at-device then
straight-up-scroll now unlocks too; 2% band still jitter-proof. (4) reverse
past the very top (transition raw ≤.005, not-focused guard) restores the
default draft; default text is now **"Hey, are you there?"** everywhere
(astro value, DEFAULT_MSG fallback, hero placeholder — "meet me at eight"
gone). Verified 390×844 matrix: journey→reverse = bubble stays; textless
replay = 3 bubbles (no dupe); typed "second msg" = stacks to 4; send→straight
up = unlocked + default restored; desktop 1401×813 panel renders. Harness:
synthetic puppeteer clicks scroll-race Lenis → drive input/button via
`evaluate` (focus/value/input-event/click) instead.

**Owner review round 11 (`85969e1`, composer = real chat):** big simplification
— `resetSend`/`maxP`/reset gates DELETED. The composer is now POSITION-locked,
not send-locked: `docked() = !sent || p ≤ 0.02`; input/send disable only while
the message is in flight (per-frame `lock = sent && p>0.02 && activeElement
!== draft` — advisory guard: a focused input is never disabled, mobile
keyboard scroll-drift can't kick the typist out). `doSend` re-arms while
docked: consecutive sends stack bubbles WITHOUT scrolling between (owner: "i
can type one and i cant do another"); auto-send only ever arms the FIRST
journey; empty manual send = no-op; journey always flies the LATEST message
(raw0 re-captured per send). `fp:plain` hero→draft now flows whenever docked
(was: only before first send). Top-reverse (crossing raw ≤ .005) clears BOTH
inputs — new `fp:clear` event, encrypt.ts listener empties the hero demo
(owner's image: stale "asdasdasd" greeted the next pass); default appears
ONLY on first load (astro value). Default text now **"sending very sensitive
data — safe here"** (owner rejected "Hey, are you there?"); base bubbles
translated PL→EN ("so, does your app actually work? 😄" / "you're about to
find out"). Verified 390×844: default flies → reverse = empty editable →
"msg A" + "msg B" consecutive sends stack (4 bubbles) → journey lands B →
top-reverse clears draft + hero → hero typing still feeds draft after
journeys.

**Owner review round 12 (`449859d`):** (1) repeat sends stack — the round-10
`isNew`/bubble-reuse branch DELETED (obsolete since round 11: scroll-replays
no longer call doSend, so every doSend that passes the guards appends a fresh
bubble; owner couldn't send "olek haha" twice). (2) capsule now DETACHES FROM
THE REAL BUBBLE: lift bezier start = `rectC(sentBubble)` (live rect, tracks
the phone during lift; stage-sticky ⇒ viewport coords == stage coords) — no
more fixed ghost spawn under the thread; verified traveler center ==
bubble center to the pixel at p=.005. (3) blinking fake caret in the empty
unfocused compose (`.c-caret`, visibility-toggled so no layout shift,
`margin-right:-5px` hugs the text start; per-frame toggle: shows only when
empty && !lock && !focused — focused inputs get the native caret). Verified
390×844: two identical sends → two bubbles; caret on/off; mid-lift screenshot
shows the copy peeling out of the chat.

**Owner review round 13 (`de4d881`):** (1) traveler is now the bubble's TWIN:
CSS matched to `.phone .m.me` (10px/7-10pad/r12), per-send
`tr.style.maxWidth = sentBubble.offsetWidth` locks the wrap width, tops
aligned (`br.top + tr.offsetHeight/2` — the meta line sits below the text so
center-align offset the twins), and `word-break: break-all` →
`overflow-wrap: anywhere` on BOTH traveler and `.m` (word wrapping when
possible, char-break only for unbreakable cipher runs) — verified 0.0px/0.2px
offset, 149==149 width, zero ghosting at detach. (2) desktop finale EVEN:
sender mirrors the recipient's growth to (0.38W, 0.56H, 0.95) — verified
symmetric to the pixel (centers 534/867 on 1401w, same y) — and both leave
together as the stage unpins. (3) caret parity: input `caret-color: #9fd6f5`
+ fake caret 1×11px — focused and unfocused indicators now identical.
(4) owner's newest-message bug: scrolling down from the device did NOT send
the fresh draft (auto-send only armed once) — new crossing-triggered implicit
send: passing lift-off (`liftRaw = raw0 + 0.02(1-raw0)`) with a non-empty,
unfocused draft disarms + re-sends, so the journey ALWAYS flies the newest
text with clean p-normalization; fast flicks can't skip it (crossing, not
window). Verified owner's exact repro: reverse to top → hero "newest message"
→ scroll down → bubble + traveler + landed all carry the new text.

**Owner review round 14 (`1fbf952`):** (1) REVERSE JOURNEY — the finale is now
a two-way toy: at the delivered end (p ≥ 0.98) Kasia's composer unlocks;
typing + send button/Enter, or typing + just scrolling up (crossing-triggered
at `dropRaw = raw0 + 0.98(1-raw0)`, `doSendBack(crossed)` — the crossing IS
the authorization, because a teleport/flick lands frames past the drop point
and a `dockedR()` re-check would fail) launches the reply BACKWARDS down the
same rail: `2:` ratchet prefix (not `3:` PreKey — honesty detail), same
seal/unseal char dynamics (plaintext at both ends by construction), mine-row
slot takeover unchanged (pure p windows), lands as a them-bubble on your
phone at `REV_LAND = 1 - T.land` with ✓✓ at p < 0.025. State: `dir: 1|-1`
picks bubble-toggle side, traveler fade end, twin-detach anchor (drop end =
reply bubble rect; lift start = `landPtBack = {spX - 60·spS, spY + 12·spS}`),
amber ring side, hint text/window. Shared `buildTraveler(prefix, ts)` +
`stack()` factored out of doSend. `landed=false` on every send WITHOUT
removing the old bubble — delivered messages stay as chat history across
direction changes. (2) headers swapped to device-owner naming (owner ask):
left phone "you"/Y-warm, right "Kasia"/K — rail YOUR DEVICE/HER DEVICE now
matches. (3) message cap 40 → 120 chars everywhere (hero maxlength, both
composers, doSend/fp:plain slices) — owner's 64-char URL paste now renders
in full on both threads. (4) desktop finale devices BIGGER + collision-proof:
`finS = clamp(min((0.30W-24)/pw, (0.56H+ph/2-76)/ph), 0.55, 1.2)` at centers
0.35W/0.65W — 351px wide at 1401×813, 24px gap at 990w, height-clamped 1.08
at 1568×721 (phones can never overlap at ANY width — also fixes owner's
broken screenshot). (5) per-frame viewport self-heal in update() (`if
(canvas.clientWidth !== W …) refit`) — devtools mobile→desktop toggles could
outrun the resize event and freeze stale W/H. (6) caret: one typing
invitation at a time — `.c-caret` added to Kasia's composer, each blinks only
in ITS empty/typable/unfocused input; unlock windows (p ≤ 0.02 vs p ≥ 0.98)
are disjoint so two carets can never coexist. Verified headless m 390×844 +
d 1401×813 + 990×900 + 1568×721: forward long-URL send, reply via button AND
via implicit scroll-up, ✓✓ both directions, history preserved through
forward→reverse→forward, no phone overlap, single caret handoff.

**Owner review round 15 (`4bf720c`):** (1) desktop reverse choreography —
`stayR = dir===-1 && !mobile`: her device skips the arrival replay (arrive
pinned 1) and stays side-stage the whole flight back, fading only at
`seg(p, .03, .10)` as the reply docks on your re-grown device (owner's
image-2 zone). (2) landing OVERSHOOT killed twice: `slotFor(thread, s)` —
the drop end / reverse-lift start is the REAL next bubble slot (one 7px-gap
below the thread's last child via live rects, `vs = rect.width/offsetWidth`
folds the phone transform in; when landed it returns the popped bubble's own
rect, which also keeps the amber ring on target) — AND the bezier control x
moved to the hold→slot midpoint, which makes x(t) exactly LINEAR (q²a +
2qt·(a+b)/2 + t²b = a+(b−a)t), so the capsule provably can't swing past the
phone; forward lift keeps the wide `liftCp` swoop. Sampled the drop at 5 p's:
x 188→158 monotone (was a +60px right bulge, owner's images). (3) thread
overflow bug (owner's before/after): `.msgs` gets `min-height: 0; overflow:
hidden` and `trimThread()` (drop oldest while `scrollHeight >
clientHeight+1`) replaces the fixed 5-cap — runs in `stack()` and on both
landing appends; the compose panel can never be pushed off-screen again.
(4) mobile reverse discoverability: hint band for dir=-1 is now `p > .955`
(was capped at .995 → invisible at the exact moment you sit at p≈1 with a
sent reply). Gotcha found while verifying: page.reload() restores scroll —
the journey auto-sends the prefill instantly and button clicks no-op
(in-flight gate); always `setRaw(0)` after reload before scripted sends.
Verified m 390×844 + d 1401×813: 5-send spam trims cleanly, slot-exact
landing with full thread, desktop reverse both-phones screenshot at p=.7,
her fade timing, reply delivery ✓✓ both directions.

**Owner review round 16 — FALSE ALARM, reverted:** owner reviewed at 150%
browser zoom by accident; all reported layout bugs (dots over devices,
"devices too big", can't type in Kasia's input) were zoom artifacts. A
started fix (finY rail-clearance + finS cap 1.0) was fully reverted —
`grep -c finY` = 0. Lesson: before chasing layout bugs from screenshots,
check reported viewport ≈ screenshot dimensions.

**Owner round 17 (`3abdaca`) — THE RELAY NODE:** owner's idea: the hero
globe returns at the relay stop — the machine is ONE node of that network.
New `shell.ts` (fibonacci dot-shell, hero's visual language, ~500 dots):
materializes mid-size at p .28–.33, grows to full .33–.425 (`anchors(p)` now
takes p; `shellR = coreR·1.16·(0.55+0.45·grow)·(1−0.55·shrink)`), iris opens
.425–.46 (dots inside the aperture slide to its rim and bunch = cut edge;
aperture `open·R·0.92` deliberately wider than the DOM clip `open·50.5%` so
rim dots never sit on the face), seals .665–.705 behind the emitted message.
Desktop: shrinks .71–.78 to a SEALED MINI-SPHERE that lingers till the old
.90–.96 fade (owner pick); mobile fades .72–.80. Machine DOM reworked: round
`.core` (radial bg, pulsing `.nucleus`, two dashed `.ring`s reusing the
`data-rotor` spin) with `clip-path: circle()` driven per frame; `.sv-stream`
now width-capped + mask-image edge fade (replaces ::before/::after);
`.slot`/`.mc-body`/`.rotor`/`.scan-*` DOM+CSS deleted. IN/OUT are canvas
ports on the shell equator (glowing slits + labels, flare on the old
slot-scan windows); intake/outlet anchors = shell equator, so wires plug
into the shell and the ports track the growing radius (endpoint motion is
(1−k)²-weighted — no visible jump; reverse = node "wakes up" as the reply
approaches). Mobile: `.mc-head` hidden (collided with caption 04's last
line), node top 46%. Desktop: nav-aware top `max(34%, coreD/2 + 102px)`
(head 34px ≈ stamp 34px symmetric column, so this pins the head to the 64px
nav's bottom edge — fixes 1568×721). All p-keyed → reply re-opens the node
in mirror automatically. Verified d 1401×813 (p .31/.44/.55/.68/.80/.93 +
full reverse with landed reply), d 1568×721 (p .55), m 390×844 (p .55/.76 +
reverse). Headless gotcha: `page.setViewport` on a used tab stalls the
setRaw rAF-stability poll — open a FRESH tab at the target size instead.

**Owner round 18 (`6e59951`):** (1) core dome brighter (owner took the
offered "glass dome" notch): `.core` radial bg #12202f/#0b1017/#060a10 →
#17293c/#0e1724/#081019, nucleus alphas .16/.05 → .22/.08, `.sv-row.mine`
occlusion band re-matched to #101c2b. (2) `yours →` overlapped its row's
timestamp (owner mobile screenshot) — mine-tag now hangs LEFT of the
stream, over the shell dots (owner-approved): desktop `left: -10px` (ends
at the 45px stream inset), mobile `left: -34px`. Verified fresh-tab
headless m 390×844 + d 1401×813 at p=.55. Note: the used-tab setRaw stall
now also hits plain `tab.goto` reuse — always verify in a FRESH tab.

**Owner round 19 (`2349f31`) — CHORD-FIT STREAM:** owner: sphere interior
should be FULLY filled with ciphers, curved to the sphere (chose curve over
plain cut — cutting slices glyphs mid-stroke; chords read as text inside
the volume). `.sv-stream` now 86%/100% of the core (mask fade 10/90);
journey measures `streamH`/`coreHalf`/`faceR = coreR−8` live, `visN`
dynamic `round((streamH+50)/(mobile?27:26))` capped by 18 DOM rows (was 9),
60 cipher cells per row (was 40; equator runs full), `chord(yTop)` =
`sqrt(faceR² − dy²)` sets each row's `left/width` per frame (mine row too);
rows are plain-cut (`text-overflow: ellipsis` removed — cut reads as
curving away). `yours →` tag now gets `left` per frame: pinned 6px left of
its row's curved edge, gliding along the inner wall over the shell dots
(CSS left values deleted, JS owns both axes). Verified fresh tabs m 390×844
(9 visible rows, symmetric chords via style dump) + d 1401×813, forward
p=.55 and reverse p=.53 (`2:` reply row chord-fit, tag at −23px).

**Owner round 20 (`75fa83a`) — BLACK HOLE CORE.** Owner idea + explicit
revert hedge: **SAFEPOINT tag `landing-pre-blackhole` = `2349f31`, pushed**
(revert = `git checkout landing-pre-blackhole -- landing/src` in the
landing worktree + commit). The exposed core now swallows light: `.core`
bg near-black (#05080d→#000), rows #4c6478 → #b9cfe2 (white-ish cipher =
the infalling light), `.hot` #fff, mine occlusion #010204. Canvas event
horizon in journey.ts (after `shellDraw`, gated `eh = open·presence`):
warm accretion halo (radial 0.8r→1.4r, rgba 255,178,102), photon ring
`rr = open·(coreR+4)` (just outside the DOM clip edge; `coreR` newly
returned from `anchors`), doppler-bright arc 2.2–4.35 rad — the ring
dilates with the iris, fully p-keyed/reversible. `.nucleus` reborn as a
breathing accretion glow ring inside the horizon (center stays black);
`.ring`s now faint warm debris dashes. Verified fresh tabs d 1401×813
(p .55 open + .445 dilating) + m 390×844 (p .55).

**Owner round 21 (`43914bc`):** owner verdict on the black hole: "S tier"
— asked for bigger horizon light. Halo 0.8–1.4r → 0.78–1.62r, peak alpha
.14 → .20; photon ring 1.8px/blur 14 → 2.4px/blur 22; doppler arc
2.6px/blur 22 → 3.4px/blur 34. Reads as a full corona over the shell dots
(solar-eclipse look). Verified fresh tab d 1401×813 p=.55.

**Owner round 22 (`4aeabcc`) — CAGED SINGULARITY:** owner ("surprise me"):
the core visible from zoom-out as a smaller, unstable, dangerous ball.
New `drawSingularity(ctx, cx, cy, r, a, t)` in shell.ts: black disc
(`0.92a` fill — swallows the shell's own light), flickering horizon ring
(`fl` = beating sines 7.3/3.1/1.2 Hz), wandering doppler hot-spot
(rotates at 0.9 rad/s, length breathes), 3 debris sparks on tight orbits
(1.25–1.5 rw, elliptical squash 0.92), rare flare spikes
(`sin(t·0.83)^24` → ring/glow/blur surge), center jitter ±1.6px. Called
in journey.ts BEFORE `shellDraw` (lattice dots pass in front = caged) at
`r = shellR·0.34`, alpha `presence·(1−open)` → visible during approach
grow AND desktop sealed-mini, hands off to the full horizon exactly as
the iris opens; instability texture is ambient time (stars class), gating
is scroll-keyed — reverse journey unaffected. Verified fresh tabs
d 1401×813 (p .38 approach + .80 mini) + m 390×844 (p .38).

**Round 23 (`960c99e`) — INDEPENDENT REVIEW + ALL FINDINGS FIXED.** Owner
asked for an independent review (code-review skill, two parallel reviewer
subagents, fixed point `4bf720c`): Standards = 0 hard violations, 3 P3
judgement calls; Spec = R17–22 faithful, no scope creep, 1 borderline P2.
Owner: "never cut corners — fix all findings." Fixes: **(P2)** flight
geometry (wires/traveler/rings/cp1/cp2) anchors on FROZEN full-size ports
(`shellRF = coreR·1.16`; a bezier endpoint receding mid-flight warps the
path); live `intakeL`/`outletL` drive only the port slits and dock with
the frozen rail during the full-size window .425–.71 (covers every
swallow/emit/ring beat); dashed rails follow the frozen flight curves but
are CLIPPED at the live shell body (`rimR = shellR+2`, pen up/down per
bezier sample) — rail always plugs into the node, capsule never leaves
its rail, no floating rail start in either direction. **(P3s)**
`fitRow()` dedupes chord-fit placement (ambient+mine lockstep);
`glowArc()` in shell.ts dedupes the warm ring idiom ×4; event horizon +
ports moved to shell.ts (`drawHorizon`/`drawPorts` — ALL node canvas
renderers in one module now); mine-tag layout reads (rects + tag width)
hoisted above the frame's first style write (no forced second reflow);
`q = mobile ? 0.6 : 1` trims shadowBlur only — dot density NEVER reduced
(harness advisory agreed: blur is the hot path, dots are the look).
Gotcha: one hashline edit landed on stale line numbers mid-refactor and
corrupted 2 lines (`.phone.recipient` opacity reset + a stray shellDraw)
— caught by immediate re-read, repaired before build. Verified fresh
tabs d 1401×813 (p .38/.55/.80 fwd + reverse .74 through the grow-back
window) + m 390×844 (p .55, 19 rows, density intact).

**Owner round 24 (`ba60276`) — AUTO-GROWING COMPOSERS.** Owner phone
screenshots: long drafts scrolled out of view in the 1-line inputs. All
three composers (hero `.enc` demo, sender pill, recipient pill) converted
`<input>` → `<textarea rows=1>` with `autoGrow()` (new in util.ts:
height='auto' then scrollHeight; MUST be called after every programmatic
value write — doSend/doSendBack clears, fp:plain sync, top-reverse reset,
fp:clear in encrypt.ts — plus once at init and on `document.fonts.ready`
because the prefilled sender draft wraps differently once IBM Plex Mono
loads). Phone pills: `max-height: 56px` (~4 lines) then inner scroll
(scrollbar hidden), `.c-row` align-items flex-end (send button hugs the
bottom line), growing pill live-trims its thread (newest bubbles stay
visible). Enter still SENDS on both phones (preventDefault — the value
never gains a newline; pasted `\n` → space, hero too). journey.ts types
went HTMLInputElement → HTMLTextAreaElement; the two per-phone
keydown/input/focus wirings merged into one loop over [draft, draftR].
Verified fresh tabs m 390×844 (hero 5-line wrap + fp:plain sync; pill
capped 56/126 with inner scroll; first-paint prefill h==sh 42, no clip)
+ d 1401×813 (Enter-send of a 120-char draft: pill collapses to 14px,
message lands on Kasia's phone at p=1).

**Owner round 25 (`77ed959`) — TLS LIGHT-TUNNELS.** Owner: the dashed
device↔sphere wires "look bad", wants modern, invited a position. Pitch
taken: caption 03 already says "ciphertext, inside TLS" → draw the wire AS
a tunnel. Dashed `setLineDash([2,7])` stroke replaced by: (1) three layered
strokes per rail (halo 10px/.05 → sheath 4px/.12 → core 1.4px/.42) forming
a soft light-conduit; (2) brightness gradient toward the node
(`0.65+0.35·near` — light bending into the well) via a linearGradient along
each visible run; (3) whole-rail breath `1+0.08·sin(t·1.6+ri·3)`; (4) 3
photons per rail drifting along ascending k = the real traffic direction
(device→node on IN, node→device on OUT; follow-up `e05ab34`: dir=-1
mirrors u so a reply never swims against the flow), radial-gradient dots, born/
absorbed softly (`sin(u·π)`), rim-skipped. Geometry untouched (frozen
flight curves + live-rim clipping from round 23). KEY: contiguous visible
runs stroked ONCE per layer — first cut stroked per-segment with round
caps and an advisory correctly flagged cap-overlap double-alpha beading
(would recreate the dotted look); rewritten to run-level polylines, u0/u1
carried per run for the gradient. First cut also too faint (core .26×.5
base ≈ half the old dash) — bumped to the shipped values. No shadowBlur
anywhere in the tunnels (mobile-cheap by construction). Verified fresh
tabs d 1401×813 (p .36 capsule riding the beam, .55 open black hole with
tunnel plugged in) + m 390×844 (p .36: symmetric luminous valley under
the sphere, photon beads, capsule on rail). Headless gotcha: the
quick-stability setRaw silently stops short of the target (Lenis eases;
"stable" ≠ "arrived") — ALWAYS re-issue scrollTo until |cur−r|<0.003
(setRaw2 pattern), a p=0.55 request had silently shot p=0.31.

**Owner round 26 (`2e34717`) — DESKTOP TUNNELS = ONE PARABOLA.** Owner:
desktop tunnels "not connected, different" vs mobile's good "parabolic
connected tunnel". Geometry dump at his 1213×693 proved it: desktop holds
(.38W/.62W) sat almost directly under the huge shell's frozen ports
(x 475/843, shellRF=184) → each rail degenerated to a floating ~14px-wide
vertical stub; no rendering can save that. Mobile reads connected because
BOTH holds share (0.5W, 0.76H) — the two wire curves FUSE at the common
endpoint into one parabola threading the sphere. Fix: desktop holds now
share (0.5W, 0.70H) too (seal/unseal moments never coexist → a shared
hold costs nothing; 0.70H clears the shell bottom by ~37px at 1213×693
and sits below the caption column at every owner viewport). Verified
d 1213×693 fwd p=.38 + d 1401×813 REVERSE p=.36 (reply `2:` capsule on
the left arc, her device side-stage, valley framed between both phones,
ports plugged). Bonus commit `e05ab34` (pre-fix): tunnel photons follow
the CURRENT journey's direction (dir=-1 mirrors u) so a reply never
swims against the ambient flow.

**Owner round 27 (`f6fc895`) — TUNNEL DIVES UNDER THE SPHERE.** Owner:
arcs "not even" + "path going into the sphere"; his idea: path should go
under the sphere, and rest "under the screen" while the black hole is
open. Root causes: (1) valley at .5W under a .55W sphere (machine CSS
left 55% on desktop) → uneven arcs; (2) ports on the EQUATOR → arcs
skimmed tangentially through the dot cloud to reach them. Fixes: valley
centered at coreC.x + sphere-relative depth (coreC.y+shellRF+84 desktop;
mobile keeps .76H); IN/OUT ports moved to the LOWER flanks (pdx/pdy =
cos/sin 0.62 ≈ 36°) on BOTH frozen (wires/flight) and live (slits)
anchors; cp x on the center→port ray (near-radial entry), cp y averaged
with holdY (rounded U — pure radial cps made a pointed V at the shared
hold; pure holdY cps would re-tangentialize the entry: ±12° join kink is
the balanced compromise); `drawPorts` gained `ang` — slits lie along the
shell TANGENT at the port, labels offset along the outward radial (an
advisory rightly blocked lower ports with hardcoded vertical slits);
wire act RESTS while the message rides inside: `insideDip` seg(.475,.51)
→(.585,.615) dims pathAlpha to 15% so the open black hole owns the
stage, re-lights for emit (chose dimming over the owner's literal
"move under the screen" — a translating wire reads as moving hardware).
Swallow/emit/rings/scan-flares all follow the port anchors automatically.
Verified d 1213×693 (p .38 rounded symmetric U + p .52 rested tunnel,
rotated port slits) + m 390×844 (p .36 valley intact, lower-flank entry).

**Owner round 28 (`5cd6723` + `ea747c1`) — HONESTY PASS + 07 CAPTION +
LAST-RELAY FINALE.** (1) Repo went PRIVATE (verified: github.com 404s) —
"public source" removed from hero tag/features card/ledger; GitHub links
dropped from nav + footer; "self-hosted" removed (owner call);
"two friends" → "built by one nerd" (owner: "I'm here alone"; ledger +
og meta). Claims precision-scoped to schema truth: link previews persist
READABLE (`linkPreviewUrl/Title/ImageUrl` text columns, caught by an
advisory) → "0 plaintext stored" became "message text: ciphertext only" /
hero "your words never reach us readable"; backups line scoped to
messages; `ea747c1`: "delete means delete" → "delete removes both sides"
(backups retain encrypted dumps until rotation). Signal claim KEPT and
verified: `libsignal_protocol_dart ^0.8.2` in pubspec — descriptive use
of the open protocol, no affiliation implied (owner asked if it's OK:
yes). New card 2: "Blind / A server that knows nothing" — names the
metadata explicitly. (2) NEW `07 / HER TURN` caption (`.cap.turn`,
data-a .955, data-b 1.2 — the fade-out window sits past p=1 so it stays
lit at the finale; slim 190px column at top 30% clears the docked sender
device on desktop, mobile centers as usual) — tells the visitor Kasia's
composer is live and the reply rides the rail back. (3) Finale = THE
LAST RELAY (frontend-design skill): outro canvas now draws a SEALED
mini-node (makeShell(300) + drawSingularity, r=.10·min(W,H), drifting at
.82W/.22H) with a through-wire running off both page edges + 3 ambient
photons that the node swallows — the story ends, the network doesn't;
amber kicker "relay nº1 · still humming"; CTA restyled as a lit PORT
(ice frame, breathing slit, skewed photon sweep on hover — replaces the
flat ice block); footer = `.f-wire` live strip (gradient sheath + 7s
crossing photon, the tunnel idiom in CSS) over a 3-part honest row:
wordmark · "no analytics on this page — your scroll stays yours"
(verified: zero external scripts in dist, fonts CSS only) · "built by
one nerd · 2026". Verified d 1213×693 (outro scene, finale 07 caption
beside device) + m 390×844 (stacked outro, footer wire). Follow-up
`7df03b6` (advisory: 1213×693 finale dropped rail dots through the tools
row): finY = min(base, railTop − 16 − ph/2) pulls the docked pair above
the rail, finS follows finY so tops clear the nav — verified phones
76–617 vs rail 633 at 1213×693; tall viewports unchanged. `graphify
update .` run (mandated for code edits — was being skipped in landing
rounds).

**Owner round 29 (`81121ba`) — DARK FACTS CHAPTER + 07 OFF THE PHONE.**
Owner: the white features/ledger slab is "a flashbang" after the dark
journey. Replaced luminance inversion with a LIFTED navy chapter:
.features #0c141f / .ledger #0a111b, dark glass cards (rgba(13,20,32,.72),
#1d2a38 keylines, inset ice top-light), half-ice h2 span, strip b → ice,
bridges shortened 18→14vh and re-aimed at the navy; nav on-light flip
DELETED (CSS + main.ts rAF block — no light zone left). Also fixed from
his mobile screenshot: the full 07 caption rendered ON the finale phone —
mobile now swaps h2+p for a `.m-short` one-liner pinned at top 6% ("her
composer is live — type, then scroll up ↑"); desktop slim column
unchanged. Hardening: `.cap, .prompt, .rail { pointer-events: none }` —
display layers can never eat composer taps (z-20 caption sat exactly over
Kasia's pill at some viewports; likely the real culprit behind the
round-16 "can't type" report). Gotcha: a hashline SWAP landed one line
off mid-file and replaced the `<section class="features">` opener with a
duplicate h2 — caught by the edit echo + advisory, repaired before build.
Verified d 1213×693 (facts chapter) + m 390×844 (one-liner clear of
phone, p=.999). Rail-clearance follow-up `7df03b6` shipped earlier in
this round-block (finY above rail, finS coupled, 1213×693: phones 76–617
vs rail 633).

**Owner round 30 (`aa57797`) — CRISP DOCKS + FOOTER POLISH + THE CORE ON
DISPLAY.** (1) Owner's "low resolution placeholder": `.phone`'s CSS
`will-change: transform` pinned a composited layer rasterized mid-journey
at ~0.4× scale — every dock showed that bitmap upscaled. phonePose now
owns the hint via a WeakMap rest-counter: 20 identical transform frames
→ `will-change: auto` (browser re-rasters at true scale, crisp), any
pose change re-arms it. Verified: transform frame-stable at rest and the
hint releases at the dock (dpr-2 pixel proof abandoned — emulated-dpr
tabs + Lenis drift mid-capture, ANOTHER flaky-tab variant; owner eyeballs
the fix). (2) Footer: `1fr|auto|1fr` grid (flex space-between pushed the
middle line 40px off-axis; now 8px = long-label min-content), single
centered column ≤820px, right label → `built by one nerd ·
github.com/Lentach` linked (profile verified 200; repo stays private).
(3) Owner asked how to reuse the black-hole core → shipped two: `og.png`
1200×630 share card (open core at the IN SEALED beat, captured headless
at exact size after an og:image:width mismatch nit) + og:url/og:image
meta; eclipse `favicon.svg` (black disc, warm ring, doppler dash-arc —
first public/ assets, dir created). Proposed next: faint open-core
watermark behind the facts cards. Meta description re-aligned to the
scoped delete claim (advisory: previews kept the round-28 overclaim).
`graphify update .` run. Centering refinement `bf7ea2d`: minmax(0,1fr) flanks; measured 599 vs 598 content-box center (innerWidth counts the scrollbar — the "8px offset" was measurement, not layout).

**Owner round 31 (`8cd5b8d` landing + `a2a91ed` on NEW BRANCH
`feat/app-logo`) — THE RELAY NODE BECOMES THE LOGO.** Owner: "it must be
our logo — pure mathematical love." Master `landing/public/logo.svg` is
GENERATED (eval cell), not drawn: exact shell.ts math — fibonacci
lattice N=500, golden angle 2.39996323, perspective F=2.6, tilt .35,
iris fully open with the rim-slide dilation — around the black-hole core
(warm horizon ring + doppler dash-arc). Brand set in `landing/brand/`
(not astro-shipped): 512/192 PNG, maskable (76% safe zone), foreground
SVG. Owner picked "new branch off master" for app wiring → third
worktree `C:/Users/Lentach/Desktop/fireplace-applogo` on `feat/app-logo`
(from origin/master): rendered `assets/icon/app_icon.png` (1024) +
`app_icon_foreground.png` (1024, transparent, 62% adaptive safe zone,
`omitBackground: true` screenshot), replaced `app_icon.svg`, fixed
`flutter_launcher_icons.yaml` colors (#0A0A2E→#000000 adaptive bg;
theme_color #FF6666→#000000 — the generator STAMPS yaml theme into
web/manifest.json, old manifest was #0175C2, an advisory caught the red
before it shipped), ran `dart run flutter_launcher_icons`: Android
mipmaps + adaptive drawables, full iOS AppIcon set, web icons +
favicon + prettified manifest. Pushed, NO deploy (owner-gated; icon
refresh needs full PWA close/reopen — never uninstall, Signal keys).
NOTE: config referenced app_icon.png/foreground.png that did NOT exist
in the repo — first real run of the icon pipeline. **V2 (owner: v1 with the
black hole "bad very bad" — wants JUST the dotted sphere): logo
regenerated as the pure CLOSED fibonacci sphere (no core/horizon), same
math; landing favicon = chunky N=130 variant (500 dots mush at 16px);
brand set + app icons re-rendered, launcher regenerated. Landing
`a99112f`, app-logo `a4c5109`.** Gotcha: reusing a browser tab for many
setViewport+screenshot cycles eventually times out the CDP session —
open a fresh tab per render batch. **V3 — THE COIN (owner flow: "on
white it looks mid → present versions → D"):** 6-variant board rendered
on white (ink / brand blue / two-tone / coin / ember / ink+ember — last
one admitted as failed); owner picked D. Master logo.svg = dark disc
#0d1420 with #23303f rim (device-bezel palette) + ice fibonacci sphere,
TRANSPARENT outside the disc (identical on any background);
`logo-square.svg` added as launcher source (iOS forbids transparency);
favicon = chunky coin. Landing `0801276`, app-logo `147ccb7`. Gotcha:
data: URLs can't load file:// images — white-proof pages must be local
files next to the assets.

**Prod go-live checklist (owner):** 1) merge `feat/landing-page` (explicit OK),
2) one-time nginx block on VM + `sudo nginx -t && reload`, 3) `cd landing ;
.\deploy-landing.ps1`, 4) verify `/welcome/` + one asset URL. PWA at `/`
untouched. Then delete `docs/design/landing-prototype/`.

## Key files

- `docs/design/landing-prototype/index.html` — round 1, fire (CLOSED)
- `docs/design/landing-prototype/round2-space/index.html` — round 2, space (B won)
- `docs/design/landing-prototype/round3-fullpage/index.html` — round 3, full page (ACTIVE)
- `docs/design/landing-prototype/NOTES.md` — questions, run instructions,
  decisions, verdicts per round
- **Not committed**: this worktree sits on `feat/user-card-rework` with the owner's
  unrelated WIP (21 unstaged + untracked files); committing docs into that pending
  PR (#84) would pollute it, and the prototypes are throwaway pending a verdict.
- No `graphify update` — docs/design artifacts only, no app code touched.

## Verification

- Both rounds, all 6 variants smoke-tested headless (1440×900): scenes animate,
  0 console errors, encrypt demo scrambles on typing, switcher cycles and is
  reload-stable via `?variant=`.
- Interaction smoke test (CDP mouse events, asserted on `window.__globe` debug
  handle): 200px drag rotated ang 1.33→2.46 rad; 6 wheel ticks zoomed 1→1.68;
  0 console errors; hint label renders at default state.
- Fixed during verification: R1-C hearth flame blowout (mode-split noise frequency
  + halved floor glow), R1-A glass card legibility (bg alpha .45→.72), R2-A stray
  invalid `addColorStop` placeholder (would have thrown), R2-B globe too faint
  (dot alpha .75→.95, arc alpha .16→.24), R2-B zoom dissolving the sphere (dots
  fixed-size + too sparse → N 650→850 and zoom-scaled radii; also restored a
  `ctx.fill()` dropped in the first patch — dots invisible without it).

## Notes for next session

- **B is the direction.** Owner confirms the interactive drag/zoom feel, then
  build the real `/welcome` page around B (Astro static + GSAP + Lenis; globe as
  a standalone canvas module) and delete `docs/design/landing-prototype/`.
- Candidate steals recorded in NOTES.md: A's stat-ledger rule; C's named-people
  idea as labels on the globe's arc endpoints.
- Surviving decisions regardless of verdict: `/welcome` routing, static-site
  stack, prototype-first loop, live encrypt demo as the signature interactive
  element (survived both rounds untouched).
- **Journey is the spine.** Build the real `/welcome`: Astro static + GSAP
  ScrollTrigger + Lenis; globe + journey as standalone canvas/DOM modules; real
  app screenshots replace stylized phones; then delete `docs/design/landing-prototype/`.
- Unrelated: owner's user-card-rework WIP (PR #84, branch-deployed to prod at
  `7ded775`) still pending merge OK — see previous entry.

## Round 32 (`f934ee5`) — short-window fixes (owner punch list)

Owner windows ~894×530 and ~826×845 (inner). Two bugs:

1. **Rest pose broke on short desktop windows** — pre-send phone was hardcoded
   `(W*0.5, H*0.60, scale 1)`: at H=530 the 567px device sat under the nav, buried
   the prompt, composer row off-screen. Now `anchors()` computes
   `restY = min(0.6H, H−20−ph/2)` (scale-free bottom stays on-screen) and
   `restS = clamp((restY+ph/2−promptB−10)/ph, .45, 1)` (visual top clears the
   prompt). Mobile pinned at restS=1 (keyboard-open H resize must not wobble the
   composer). `restX = W/2 − pw(1−restS)/2` compensates phonePose's s=1-only
   centering; the lift/dock lerps (both branches) start from restX/restY/restS.
   — Gotcha found live: promptB cached via gBCR while the journey was OFF-SCREEN
   → huge viewport-relative bottom → restS clamped to floor at 1225×1134.
   Fixed: `offsetTop+offsetHeight` (stage-relative), cached per W/H.
2. **Relay label wrapped + clipped** — `.mc-head .lbl` at coreD=46vh<400px
   (H<~870) wrapped to 2 lines, head grew past the 102px top-clamp budget, text
   cut under the nav. Fix: `white-space: nowrap` (overflows the machine column
   symmetrically; fits any viewport ≥ ~520px).

Verified headless: 894×530 (prompt clear, top 182 > promptB 173, bottom 510),
826×845 (label single line, top 67 ≥ nav 64), 1225×1134 (rest pose byte-identical:
bottom 964, h 567), 390×844 (unchanged: bottom 724). Prompt "ghost" in headless
captures = its `transition: opacity .6s` caught mid-fade by instant scroll jumps —
computed opacity 0, not a product bug.

## Round 33 (`ade58ef`) — copy: “one nerd” → “one guy” (ledger strip, footer, og:description; 3 occurrences, grep-verified in dist).

## Round 34 (`e0d02cf` landing) — app CTAs open in a new tab
`target="_blank" rel="noopener noreferrer"` on both `{app}` CTAs (nav OPEN APP + outro Open Fireplace) — owner wants the landing (black-hole vault) to stay open behind the app. Anchor links untouched.

## Cosmic login screen (`50565cc`, NEW branch `feat/login-cosmic` off origin/master, applogo worktree)
Owner: login screen "bad and ugly" — glyph wallpaper + fire/red/teal color soup. Rebuilt as the cosmic front door matching the landing:
- `lib/widgets/star_field_background.dart`: STATIC seeded starfield painter (Random(1420), density area/7000 clamp 80–340, quarter ice-tinted, every-23rd halo star, faint radial glow at .5W/.34H) over `cosmicBg`. No animation ⇒ reduce-motion safe, `shouldRepaint false`.
- `RpgTheme` cosmic tokens mirroring landing.css: bg `#070D16`, input `#0A111B`, cardBorder `#1D2A38`, ice `#8FD8FF`, onIce `#04121C`, text `#EEF6FB`, muted `#8FA8BC`.
- `GlassTheme.cosmic` preset (fill `0x8A0D1420`, ice border) — advisory catch: without it a LIGHT chat theme painted a white login card.
- `auth_screen.dart`: `_cosmicTheme()` local Theme override (colorScheme.primary→ice, inputDecorationTheme borders/fill/hint, elevatedButtonTheme ice/onIce, FireplaceColors + GlassTheme extension swap); title glow amber→ice; tabs ice-on-navy via folded `_tab()` helper; glyph `ChatBackgroundPattern` dropped.
- Verified: analyze clean ×4 files, rendered via `flutter run -d web-server :8091` (hub job, stopped) + screenshots 1200×900 & 390×844, `auth_gate_session_restore_test` green. Branch pushed, graphify run. NOT merged — owner reviews.

## Cosmic login round 2 (`ecc9aaf`, feat/login-cosmic) — exact brand match
Owner side-by-side: landing vs login colors differed. Root causes: cosmicBg #070D16 + radial ice glow = navy cast (landing journey stage is FLAT #000); glowing 'Fireplace' with offset shadow = ghost double (landing mark is flat). Fixed: cosmicBg → #000000, glow deleted from StarFieldBackground, title → flat two-tone `FIRE`(cosmicText)+`PLACE`(cosmicIce) Text.rich in Press Start 2P (uppercase, matching nav mark `FIRE<b>PLACE</b>`). Analyze clean, re-rendered 390×844 verified. Branch pushed — still awaiting owner review/merge; NOT deployed (OPEN APP serves master until merged).

## Cosmic login round 3 — rebuilt on the REAL cosmic theme (`b023c0f`, feat/login-cosmic force-pushed)
Owner rejected ice/white wordmark; wanted the app's actual cosmic blue + a non-pixel font + a new motto. KEY discovery: an unmerged, already-deployed `feat/cosmic-theme` branch (3 ahead of master) already owns the real cosmic palette + an ANIMATED starfield:
- `theme/rpg_theme.dart`: `_cosmicSpec` / `RpgTheme.themeDataCosmic`; tokens `accentCosmic #8FD8FF` (--ice), `secondaryCosmic #1D6FD6` (--blue), `backgroundCosmic #05070D`, `mineMsgBgCosmic #1D6FD6`, etc.
- `theme/glass_theme.dart`: `GlassTheme.cosmic` (fill 0x800E1826, `onGlassAccent #A5DBFF`).
- `theme/cosmic_theme.dart`: `CosmicBackdrop.starfield` (baseColor #04060C, starColor #BEDCF0, density 120).
- `widgets/starfield_background.dart`: 1:1 port of the landing hero starfield — Ticker twinkle, RepaintBoundary, lifecycle-paused off-screen, STATIC under reduce-motion.
- `widgets/chat_background_pattern.dart`: if `CosmicBackdrop.maybeOf` != null → renders `StarfieldBackground` over baseColor (the ONE wallpaper path).

DECISION: my off-master `feat/login-cosmic` (parallel `cosmicBg/cosmicIce/...` tokens + a static `star_field_background.dart`) was duplicate infra. `git reset --hard origin/feat/cosmic-theme`, rebuilt `auth_screen.dart` from that base — so login-cosmic now BRANCHES FROM cosmic-theme and MUST land after it.
New auth_screen: wraps content in `Theme(data: RpgTheme.themeDataCosmic)` → login is ALWAYS the cosmic front door regardless of saved chat theme; card/inputs/button/starfield all from the one theme. Owner picks applied: wordmark = **Archivo 900** (`google_fonts`, was Press Start 2P) FIRE(onSurface white) + PLACE(`GlassTheme.cosmic.onGlassAccent #A5DBFF` — the exact board-N swatch); motto = **M4** `authTagline` → EN 'Messages only two people can read' / PL 'Wiadomości, które przeczytają tylko dwie osoby' (both ARBs + `flutter gen-l10n`). Dropped: parallel cosmic tokens in rpg_theme, my static starfield widget, my GlassTheme.cosmic preset (all superseded by cosmic-theme's), 'Enter the realm'/'Wejdź do krainy'.
Verified: analyze clean, `auth_gate_session_restore` green, rendered 390×844 (Archivo mark + #A5DBFF PLACE + M4 PL motto + animated starfield). Boards `docs/design/wordmark-board{,2,3,4}.html` were the pick vehicles (owner: N split → F6 Archivo → M4).
Topology now: cosmic-theme (unmerged, deployed) → login-cosmic (`b023c0f`, off cosmic-theme). Merge order: cosmic-theme first, then login-cosmic.

## SHIPPED TO PROD — 0.0.121 (cosmic theme + cosmic login), master `1ff70d1`
Owner approved the login design + combined deploy. Handoff's "PR #84 unmerged" was STALE: git showed user-card-rework tip == merge-base of master (already an ancestor of master), i.e. user-card is ALREADY on master — no regression risk. cosmic-theme had also advanced past where I branched login (tip `cf497d5`, a docs-only STARFIELD_SPIKE change, not in login-cosmic).
Merges (in the `fireplace-ping-deploy` worktree, the one holding master): `git merge --ff-only origin/feat/cosmic-theme` (→ cf497d5) then `git merge --no-edit origin/feat/login-cosmic` (clean 'ort' merge, only auth_screen.dart + 5 l10n files; disjoint from cf497d5). Version bumped 0.0.120→**0.0.121** (0.0.120 was the ephemeral PR#84 prod build; distinct bundle → distinct version, per runbook release contract). Full `flutter analyze` clean; `cosmic_theme_test` + `auth_gate_session_restore_test` green. Pushed master `1ff70d1`.
Deploy (frontend-only; `deploy-web.ps1` is known to die exit-21 under the harness, so did the runbook steps by hand): `flutter build web --release --no-wasm-dry-run` with BASE_URL/GIT_COMMIT=1ff70d1/BUILD_TIME/VAPID defines → scp build/web to VM `~/web-staging` → guarded atomic swap into `~/fireplace/frontend-build` (test version.json && rm -rf && mv && chmod -R a+rX) → PUBLISHED_OK. Verified: `/version.json`=0.0.121, `/health`={ok,ok}, `/version`(backend)=0.0.120 (unchanged — frontend-only). Rendered prod login headless at 390×844 = cosmic front door confirmed (had to `page.setCacheEnabled(false)` + cache-bust; the persistent Chromium served old HTTP-cached shell first — server main.dart.js mtime 03:38 = fresh).
NOTE for owner: real-user PWAs get 0.0.121 on next full close+reopen (never uninstall). Branches cosmic-theme / login-cosmic / user-card-rework are all in master now — safe to delete. Backend still 0.0.120; no backend change shipped.

## feat/app-logo merged to master (`ac0085b`)
Coin launcher-icon branch merged clean (45 files, all icon assets — android mipmaps/adaptive, iOS AppIcon set, web icons/favicon, flutter_launcher_icons.yaml, manifest.json theme_color+background #000000; disjoint from cosmic/login/user-card). Pushed. NOT yet deployed — the PWA coin icon goes live only on the next web deploy (would be 0.0.122). Remaining unmerged branch: feat/landing-page (42 ahead) — go-live is separate (nginx + deploy-landing.ps1), pending owner decision on repo layout (monorepo vs standalone site repo).

## SHIPPED: coin icon (0.0.122) + landing page LIVE at /welcome
Owner: deploy the coin + take the landing live (website stays in the monorepo — decided against a standalone site repo: solo dev, private repo, safety-copy must stay atomic with code, same VM/domain; `landing/` stays cleanly extractable later).

**Coin (0.0.122, master `fddf4a3`):** bumped pubspec 0.0.121→0.0.122, built web release, scp+guarded swap into frontend-build. Verified `/version.json`=0.0.122; coin assets served 200 (favicon.png 485b, Icon-512 58486b, Icon-192 18483b, maskable-512) matching server files. Real devices refresh the icon on PWA close+reopen.

**Landing (master `80a5dcb`):** merged feat/landing-page (clean — touches ONLY landing/, no overlap with master). Built dist (Astro, base=/welcome → dist/index.html + assets/ + og.png + logo.svg + favicon.svg). Uploaded to staging, guarded swap into `~/fireplace/landing-build/` (keeps landing-build.old), chmod a+rX. One-time nginx block added to /etc/nginx/sites-enabled/fireplace (inserted before the Flutter `location /` catch-all, via python to /tmp then sudo swap with timestamped backup + `nginx -t` gate + auto-rollback):
  `location = /welcome { return 301 /welcome/; }`
  `location ^~ /welcome/ { alias /home/ubuntu/fireplace/landing-build/; index index.html; }`
`nginx -t` ok → reload. Verified: /welcome→301→/welcome/ (200, correct <title>), first JS asset 200 application/javascript 43581b, PWA at / untouched (still 0.0.122). Rendered live hero headless (dot-globe + compose demo working).

ALL feature branches now merged to master. Only stale merged branches remain (deletable). Landing subsequent deploys: `cd landing ; .\deploy-landing.ps1` (no nginx reload needed). nginx backup: /etc/nginx/sites-enabled/fireplace.bak.1784434246.

## Landing post-launch fixes (master `a0e453b`, redeployed) — owner review
Two live bugs:
1. **Hero dot-sphere stretched vertically.** Root cause via live canvas metrics: globe backing store 1581x1000 (aspect 1.581) but CSS box grew to 1265x870 (1.454) — the hero box settles TALLER after init (fonts/layout/scrollbar) and globe.ts only re-fit on window `resize`, so the stale backing aspect stretched the sphere. Fix: `ResizeObserver(refit).observe(canvas)` in globe.ts (re-fits on ANY box change). Verified prod: backing==css aspect (1.046==1.046), round.
2. **Devices drift right / sender not on left / overlaps flight path.** Root cause: `phonePose` only centers at s=1 (visual center = x + pw*(1-s)/2); every scaled beat drifted the phones RIGHT by pw/2*(1-s) (~63px), so sender sat ~0.28W (over the capsule) not 0.20W, and the finale pair sat off-center ("not even"). Fix: compensate at the call site with the LIVE scale — `x - A.pw*(1-s)/2` for sender, recipient, AND the pre-send rest pose (advisory catch); `restX` reverted to raw W*0.5; added `pw` to anchors() return. Verified: sender 0.197W (left), recipient 0.785W (right) even, rest pose 0.493 (centered), relay-beat capsule no longer overlaps the phone.
Both built, verified on local preview + prod (cache-bypassed), landing-build swapped. journey.ts + globe.ts committed to master.

## Landing: Bob/Kate rename + responsive device split (master `646dd27`, deployed)
1. **Renamed journey actors** to Bob (sender) + Kate (recipient): phone headers (you->Bob ava B, Kasia->Kate), rail labels (BOB'S/KATE'S DEVICE), keytags (Bob's/Kate's key), captions 01-07 (his/Kate's; "ONLY KATE'S PHONE", "KATE'S TURN"), journey.ts runtime strings ("Bob's ->" mine-tag, "the message is on its way"). HERO deliberately KEPT the visitor "you" POV (product pitch). Grammar tightened per advisory ("the instant Kate is reachable", "opened only on his"). NOTE for owner: this made the journey third-person; if you prefer the punchy 2nd-person "your message" voice back, it's a quick revert of the caption prose only.
2. **Responsive device split** (owner: at ~1213w-tall the docked device covered the path). Root cause measured: relay lower-flank ports are fixed-px (height-scaled), sphere sits at 0.543W; the 0.20/0.80 %-split left only 14px between Kate's inner edge and the right port at narrow widths (clean on wide desktop). Fix in anchors(): moved coreC/shellRF above device positions, compute `outFrac = clamp(max(0.80, (coreC.x + shellRF*cos(0.62) + 44 + pw*phoneSv/2)/W), 0.80, (W-halfDev-8)/W)`, devices = W*(1-outFrac) / W*outFrac (symmetric about 0.5W → even; clamped on-screen). Verified: 1213x1000 gap 14->44px (recip 0.815, sender 0.173, both on screen), 1568x714 unchanged (0.792, gap 175), 803 rail labels fit + path clear (recip right edge 23px margin — tight but on-screen). NOTE: below ~950w desktop the pushed device nears the edge; if owner hits a too-narrow case, shrink the sphere (coreD width-cap) as a follow-up.
Both built + deployed (landing-build swap) + prod-verified cache-bypassed. (globe stretch + phonePose X-drift were the prior commit a0e453b.)
