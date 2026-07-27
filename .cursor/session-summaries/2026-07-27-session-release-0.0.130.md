# 2026-07-27 — RELEASED: `feat/nav-rework` merged as frontend 0.0.130

**PR #98 merged (`ec60324`), master deployed, smoke 5/5.** Frontend **0.0.130 /
`ec60324`** is live. Backend deliberately untouched at 0.0.127/`3861166` —
nothing on this branch touched it. Local branch `feat/nav-rework` deleted
(merged); the remote branch is kept for the PR reference.

Owner's word: **"pr merge make master great again"**.

## What shipped

The whole bottom-nav rework, plus the last two Settings glyphs that were still
speaking a foreign shape language. 18 commits, 9 files, +1259 −164.

1. **Nav glyphs**, owner-picked per row from rendered A/B: hex speech bubble for
   Chats, three-cell comb for Contacts, gear-wearing-the-cell for Settings.
   `ConsoleGlyph.localNode` → `.settings`.
2. **Selected state**: INSET fill inside outlines that stay visible. The gear
   states selection by WEIGHT (1.8 → 2.5) because its teeth are spokes rooted
   inside the body and any fill swallows their roots.
3. **Per-glyph motion**, all transient: comb cells fly apart and reassemble, the
   bubble lifts, the gear turns one tooth pitch. Zero at both ends.
4. **Tab travel**: an edgeless glass lens that glides under the active tab,
   stretching toward its destination and flattening as it goes, and the tab you
   tap waits 160ms so the lens DELIVERS the selection rather than racing it.
5. **`password`** is a padlock whose body IS a cell, drawn as a true U shackle.
   **`language`** is the meridian globe wearing the cell. `appearance`
   deliberately untouched, per the owner.

## Verification

- CI on PR #98: **both jobs SUCCESS**, `MERGEABLE` / `CLEAN` before merge.
- Local before merge: **879 passed / 4 skipped**, analyze 0 issues over `lib/`
  + `test/`. Backend untouched at 536.
- Post-deploy smoke **5/5**: `/health`, `/version.json` 0.0.130, backend
  `/version`, literal bundle SHA `ec60324` in `main.dart.js`, app boot.
- **Three independent review sub-agents** before merge — Standards (3 findings,
  worst a hardcoded `Color(0xFF000000)` fallback, fixed), Spec (0 findings,
  including confirmation that every device-rejected treatment is absent from the
  END STATE), and a delta review of the post-review fixes (0 findings). The
  delta reviewer also corrected a false premise planted in its own prompt (`??`
  does short-circuit its right operand), which is the independence working.

## Notes for next session

- **Master is the release.** Live frontend 0.0.130 / `ec60324`. Never infer what
  is live from `git log` — read `/version.json`.
- **Owner must fully close + reopen the PWA.** NEVER uninstall or clear site
  data (wipes E2E keys).
- **One deliberate open item, not a bug:** `_activeStroke`, `_selectedSpin` and
  `_motionOffset` in `console_glyphs.dart` are three per-glyph switches beside
  `_draw`/`_opticalNudge` (Fowler: Repeated Switches). The reviewer is right
  about the file's data-driven idiom, and the owner was told plainly it is
  tidiness with zero visible benefit. **Do it in ONE pass when a fourth glyph
  needs motion — never piecemeal**, because half of it leaves two conventions in
  one file. `_motionOffset` is the hard part: it is a strategy, not a scalar,
  and depends on geometry being re-centred at resolve so `_c` is the true
  centre.
- **`appearance` is settled, not open** — owner: "appearance leave as it was".
- **Five marks are still non-hex objects** (`devices`, `webStorage`, `media`,
  `metadata`, `cache`). Flagged; owner said "rest is ok". Do not re-litigate.
- **Dependabot #95 is still open and still untriaged in the tracker** —
  `brace-expansion <= 5.0.7`, high, `backend/package-lock.json`. Analysis done
  this session: **every copy is `dev: true`**, reachable only through
  eslint/jest/nest-cli, and the container ships prod deps only, so it is not
  runtime-reachable. Fix is a lockfile bump on master, needs a worktree, a lock
  diff and the 536 backend tests before anyone calls it quick — npm's resolver
  can rewrite neighbouring entries.
- Queued, none promised: `ListView` rewrite of the honeycomb for >200 contacts;
  "sent invites as ghosts" (needs `friends.service.ts getPendingRequests` to
  stop filtering `receiver: { id: userId }`); Chats `+` as a honeycomb picker.
