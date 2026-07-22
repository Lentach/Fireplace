# Landing page prototype — NOTES

**Status: SUPERSEDED — the real page is built.** Production source lives in
`landing/` (branch `feat/landing-page`, Astro + Lenis, all four rounds folded
in). These prototype files are kept ONLY until the owner confirms the deployed
`/welcome` page on-device — then DELETE this whole directory.

## Question

Which aesthetic should the Fireplace landing page (future `/welcome`) be built
around? Iterated in rounds; each round is 3 radically different stagings.

---

# Round 4 — MESSAGE JOURNEY (`round4-journey/index.html`) · **WINNER**

Owner idea (overnight, building on the confirmed "what the server stores"
segment): an interactive journey following one message from the Send click to
delivery, with the server as one stop. Question: **does a user-triggered
scrollytelling journey work as the page's spine?**

**VERDICT (owner, 2026-07-17): emphatic yes — "crying rn its great". The
journey is the spine of the production page.**

**Iteration 3 (owner: server = "enigma machine"):** the server stop is now the
**RELAY MACHINE** — "fireplace relay nº1": header with 3 rotors (I/II/III,
dashed dials that spin as the message passes, scroll-driven + idle drift),
body with IN/OUT slit slots (scan-line flash on swallow/emit), the ciphertext
stream as the machine's window, stamp "routes everything · reads nothing".
Sequence: capsule flies to the intake slit → scan flash + ring → shrinks into
the slit (swallowed) → hidden while its row docks highlighted in the window and
rotors turn → emitted from the OUT slit (scan + ring) → second arc to her phone.
HONESTY GUARD: unlike a real Enigma the machine transforms NOTHING — caption
"In sealed. Out sealed."; the capsule enters and exits as the same ciphertext.
Rail stop renamed "our server" → "relay".

**Iteration 2 (owner transition feedback, same day):**
- Capsule now launches FROM the sent bubble's position via a bezier lift (no
  more mid-air teleport); glow trail follows it on both wire legs.
- Server stop got the round-3 stream back: 9 dim ciphertext rows flow
  bottom→top continuously (time-driven); YOUR row docks into the queue as an
  opaque highlighted row ("yours → 08:12:03 3:…") and stays dimmed after relay
  (server keeps ciphertext for delivery — honest).
- Impact rings: server dock, arrival at her phone, and a gold ring at the
  on-screen landing.
- REAL landing: at p>.955 the traveler vanishes and the message is appended
  INSIDE her chat as a left bubble (pop-in animation); sender's meta flips
  ✓ → ✓✓. Fully reversible on scroll-back (bubble removed, ticks revert).

Flow: page opens LOCKED on a live conversation window ("Where does a message
actually go?"). User edits/keeps the draft, presses ➤ — scrolling unlocks and
scroll position drives the journey (800vh sticky stage, rAF-driven):

1. **01 LIFT-OFF** — sent bubble detaches from the chat, phone shrinks aside.
2. **02 SEALED** — per-char scramble plaintext → `3:base64…` (staggered, hot
   glow), key tag pinned to the phone: "your key — never leaves this device".
3. **03 IN TRANSIT** — bubble morphs to a glowing capsule, rides a dashed
   bezier arc (TLS caption).
4. **04 OUR SERVER — THE HONEST STOP** — capsule docks; the stored row types
   itself in: `"encryptedContent" '3:…'`, `"messageType"`, `"deliveryStatus"`,
   `"createdAt"` (real quoted-camelCase columns) + "no key on this machine".
5. **05 RELAYED** — second arc; recipient phone slides in.
6. **06 UNSEALED** — chars scramble back to plaintext, lands in her chat,
   "✓✓ delivered", her key tag.
7. **End card** — "That's the whole story. We're just the courier." + CTA +
   replay (reloads).

Journey rail (bottom): your device · wire · our server · wire · her device,
stops light up with progress. All stage copy technically true per CLAUDE.md
§6/§7.

Known prototype limits: desktop-first; scroll driven by plain rAF (production:
GSAP ScrollTrigger + Lenis); phones are stylized stand-ins (production: real
screenshots); harness-only race when chaining programmatic scrolls (not a UX
bug). Relationship to round 3: the journey is the MIDDLE of the full page —
hero (globe) → journey → feature trio → ledger → outro.

---

# Round 3 — FULL PAGE (`round3-fullpage/index.html`) · CLOSED (flow validated; journey takes the middle)

After B won round 2, owner shared competitor references (zangi.com, wire.com,
getsession.org) — verdict "they're mid, we can do a lot better." Round 3 answers:
**does the full page FLOW work?** One composition, no variants:

1. **Hero** (black): interactive dot globe (drag rotate; **Ctrl+scroll** zoom so
   plain scroll still scrolls the page — embedded-map convention), Session-grade
   headline "Messages only two people can read.", live encrypt demo.
2. **Bridge** dark→light (Wire's rhythm, minus their stock-photo slop).
3. **Product reveal** (light): stylized phone mockup with Zangi-style annotation
   callouts pinned to UI facts + a **live "what the server stores" ciphertext
   log ticker**. Headline "You see the conversation. We see noise."
4. **Feature trio** (light cards): Sealed / Yours / Ephemeral — all claims true
   per CLAUDE.md (§6/§7).
5. **Honest ledger strip**: 0 plaintext · E2E default · public source ·
   self-hosted · built by two friends. NO fake trust signals (no download
   counts, no testimonials). "Open source" deliberately downgraded to
   "public source" — repo is public but has NO LICENSE file; add a license
   if the stronger claim is wanted.
6. **Outro** (black, starfield): "Talk like no one's listening." + CTA.

Production-page TODOs baked into this skeleton: replace stylized phone with
REAL app screenshots; nav needs a scroll-aware dark/light flip (dark glass
looks muddy over light sections); scroll reveals via IntersectionObserver —
real build uses GSAP ScrollTrigger.

## Round 3 verdict (owner, partial — 2026-07-16)

- **CONFIRMED: the "what the server stores" live ciphertext segment** — owner
  explicitly approved it. It is a keeper for the production page.
- Flow works? _____ (full-page verdict still pending)
- Section-level changes: _____

---

# Round 2 — SPACE (`round2-space/index.html`) · CLOSED (B won)

Owner reference: fin.com via land-book 97118 — "space, planets, black theme,
visible connection links around the planet." Extracted from the reference:
planet-horizon composition, thin glowing arcs, quiet serif, tiny mono stat
labels on hairline rules, huge black negative space.

## Round 2 variants

- **A — Planet Horizon** (fin-faithful): warm-gold planet limb rising from the
  bottom edge, arc pulses crossing it, centered Cormorant Garamond serif,
  stat ledger rule at the bottom. Quiet-luxury cinematic; gold bridges the
  ember brand into space.
- **B — Dot Globe** ★ WINNER: full rotating 3D fibonacci dot-sphere (GitHub-globe
  style) right of center with 3D arcs riding the rotation; brutalist Archivo caps,
  asymmetric split, cold ice-blue palette. Now interactive: drag to rotate
  (inertia, auto-spin resumes when idle, vertical drag tilts) + scroll to zoom
  (0.55–2.3×, dots/arcs scale with zoom); hint label fades on first interaction.
- **C — Constellation**: no planet — a drifting star-map where nodes are named
  *people* (your contacts) and message pulses travel the links; Spectral
  extralight serif, violet accent. "The network of people you trust" as hero.

## Round 2 verdict (owner, 2026-07-16)

- Winning variant: **B — Dot Globe** ("the blue dot planet"). Owner asked for
  rotate + scope → implemented as drag-rotate + wheel-zoom (see above).
- Next: owner confirms the interactive feel, then build the real `/welcome`
  page around B (Astro static + GSAP + Lenis; globe as canvas module).
- Open steals to consider: A's stat-ledger rule; C's named-people nodes could
  label the globe's arc endpoints with contact names.

---

# Round 1 — FIRE (`index.html`) · CLOSED (theme dropped)

## Round 1 question

Does the "fire shader + burn-to-ciphertext" aesthetic feel right? Which of
three stagings should the real page be built around?

## How to run (both rounds)

Open the round's `index.html` in a browser (double-click; no build/server).
Switch variants with the floating bottom bar, `←`/`→` keys, or `?variant=A|B|C`.
Type into the "Type something private" input on any variant — the "what our
server sees" line re-encrypts with a scramble animation (real `3:` PreKey wire
prefix from CLAUDE.md §7).

## Round 1 variants

- **A — Inferno Hero**: full-bleed GLSL fire wall (reacts to cursor x), giant
  gradient display type (Unbounded), glass encrypt card floating over the flames.
  Loud, cinematic, maximal.
- **B — Ash Minimal**: near-black, drifting embers only, Instrument Serif italic
  headline ("Your words, only ashes on the wire."), the encrypt demo IS the hero.
  Stark, typographic, quiet-confidence.
- **C — Warm Hearth Editorial**: asymmetric two-column grid, fire framed as a
  literal hearth ("Fig. 01"), Fraunces editorial type, warm brown-paper palette,
  feature ledger list. Cozy, crafted, matches the "fireplace = warmth" read.

## Decisions already made (session 2026-07-16)

- Landing is a **separate static site** (NOT Flutter web): app stays at `/`,
  landing at `/welcome` (or subdomain) — zero risk to installed PWA scope and
  local E2E Signal keys.
- Proposed real-page stack: Astro static + GSAP ScrollTrigger + Lenis + raw
  GLSL (OGL). Deploys as plain files via the existing nginx atomic-swap pattern.
- Full concept parked for after aesthetic verdict: scrollytelling "journey of a
  message" (plaintext burns → ember travels wire → rekindles on recipient device).

## Round 1 VERDICT (owner, 2026-07-16)

- Fire/burn aesthetic **dropped** after seeing all 3 variants; owner supplied
  the fin.com reference that spawned round 2.
- The GLSL shader / particle / scramble machinery stays reusable; the
  burn-to-ciphertext "what our server sees" demo survived into round 2 unchanged
  (owner only rejected the fire skin, not the demo).
