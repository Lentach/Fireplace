# 2026-08-18 — GitHub Actions billing wall diagnosed, repo made PUBLIC, 0.1.16 shipped

Continues `2026-08-17-session-attachment-sheet.md`. Three things happened, in order:
the CI blackout was explained with numbers, the repo was flipped public to end it,
and the popover-anchor fix finally shipped as **0.1.16**.

---

## 1. The CI blackout was BILLING, not GitHub and not our code

Every job on every branch had been instant-failing since ~15:06Z 08-17: **2–4 s
wall time, `steps: []`, no logs.** Two earlier entries in `LATEST.md` guessed
"likely an Actions minutes/spending limit". It was. Proof, not inference:

```
gh api repos/Lentach/Fireplace/check-runs/95531203146/annotations -q '.[].message'
→ "The job was not started because recent account payments have failed or your
   spending limit needs to be increased. Please check the 'Billing & plans'
   section in your settings"
```

`gh api users/Lentach/settings/billing/actions` 404s and `users/Lentach` needs the
`user` scope (`gh auth refresh -h github.com -s user`), so the usage number was
**measured from the run history instead** — sum each job's `started_at → completed_at`,
rounded up per minute, which is GitHub's own billing rule:

| job | minutes since Aug 1 | runs | avg |
|---|---|---|---|
| Flutter analyze and tests | 1072 | 167 | 6.4 |
| E2E wire harness | 482 | 167 | 2.9 |
| Backend tests | 263 | 167 | 1.6 |
| E2E session Web Lock probe | 214 | 167 | 1.3 |
| Dependabot | 53 | 21 | 2.5 |
| **total** | **≈2084** | 689 jobs | |

Free-plan **private**-repo allowance is 2000 min/month. 2084 > 2000. That is the
whole story. Reusable recipe (188 runs, ~1 min):
`gh api repos/.../actions/runs?per_page=100&page=N` → `.../runs/<id>/jobs` → sum.
**`/actions/runs/<id>/timing` reports `total_ms: 0` on this repo — do not trust it**,
compute from job timestamps.

## 2. PR #147 — stop paying for prose (`4b7c807`)

**609 of those 2084 minutes were commits that changed only prose**, and **583 of
the 609 touched no `CLAUDE.md` at all** — overwhelmingly session summaries under
`.cursor/session-summaries/`. Every one of them ran the full 12-minute 4-job matrix.

`ci.yml` now has `paths-ignore` on both triggers (`.cursor/**`, `docs/**`,
`README.md`, `AGENTS.md`, `CONTEXT-MAP.md`) plus `concurrency: cancel-in-progress`
per ref.

- **`CLAUDE.md` is deliberately NOT ignored.** `scripts/verify-claude-*-test-counts.mjs`
  gate the documented test counts; skipping CI on a CLAUDE.md edit would let a wrong
  count sit unverified. That guard costs 26 min/month. Keep it.
- **`paths-ignore` is duplicated per trigger on purpose — Actions does not support YAML anchors.**
- Validated by **replaying the filter against the real 188-run history**, not by
  arithmetic: 48 runs skipped, **583 min saved, 0 code or CLAUDE.md commits wrongly
  skipped**, projected 1501/2000.
- **⚠️ Trap for whoever enables branch protection now that the repo is public:** a
  skipped workflow never reports, so if these four jobs are marked *required*, a
  docs-only PR hangs forever on "Expected — waiting for status". Replace
  `paths-ignore` with the dummy-job pattern (second workflow, inverted `paths`,
  same four job names, `exit 0`) if that day comes. Until then protection was
  literally unavailable: `gh api .../branches/master/protection` → 403 "Upgrade to
  GitHub Pro or make this repository public".

## 3. Repo flipped PUBLIC — the pre-flip secret audit

Owner chose public over paying. **Public exposes the entire immutable history, not
the tip**, so a full-history scan ran first (scout, read-only, all refs).

**Cleared — searched and NOT present in any ref:** no PRIVATE KEY/OPENSSH/RSA/EC
blocks; no `AKIA`/`ghp_`/`xox*`/`sk-` tokens; no committed `JWT_SECRET`, VAPID
private key, Postgres password, or `DATABASE_URL` with creds; `.env`,
`backend/.env`, `frontend/.env`, `*.pem`, `*.p8`, `*.p12`, `*.key`, `id_rsa*`,
`*.jks`, `deploy-web.config.ps1` were **never tracked at any commit**;
`firebase_secrets.dart` was always `TODO_REPLACE`. The one "AWS key" hit was
`.githooks/pre-commit`'s own detection regex.

**Two real credentials WERE in history. Both tested live, both dead:**

| secret | where | probe | result |
|---|---|---|---|
| Context7 API key `ctx7sk-a18dff5a-…` | `.claude/settings.local.json`, commits `2507073`→`fdd3aa2`, untracked at `a6ffcac` | `GET context7.com/api/v1/search` with Bearer | **401 `invalid_api_key`** |
| Contact-inbox bearer `547ac8b6…071d95` | `.cursor/session-summaries/2026-07-22-session-inbox-extraction.md`, `2a70e38`, redacted `10f733d` | see below | **rotated** |

The 2026-07-27 audit note claiming the Context7 key was "still live, revocation
owed" is **STALE — it is revoked.** Corrected here.

**⚠️ Method note worth keeping — a 404 is not proof of revocation.** The inbox
probe first returned 404, which was reported as "dead"; that was wrong reasoning,
because *every* path under `/contact` returns 404 from the public side, so 404
could equally have meant "route gone". An advisory caught it. Resolved properly on
the VM: `fireplace-inbox` is **Up 3 weeks (healthy)** with nginx `location /contact`
present, and

```
current key from ~/fireplace-inbox/.env → 200
leaked key 547ac8…                      → 404
```

Different first-6 (`99980a` vs `547ac8`) ⇒ genuinely rotated, and the 404 is the
service's documented bad-key response (`production-vm-deploy.mdc` line 76), proven
to be rejection rather than a missing route because the *same URL shape* answers
200 with the current key.

**Accepted, now world-visible and unrevertable:** the Firebase Android API key in
`google-services.json` (public-by-design, ships in every APK — restrict with App
Check, do not rotate); prod infra `51.68.138.13` / `ubuntu` / `fireplace.ignorelist.com`
/ full deploy topology (SSH is key-only, so disclosure not credential); owner's
personal email on 865 commits.

**Flipping public restored CI instantly** — PR #145 and #147 both went from
instant-fail to **4/4 SUCCESS** on rerun with no code change. That is the
cleanest possible confirmation the wall was billing.

## 4. 0.1.16 shipped — the iOS popover anchor (PR #145, `6a35042`)

Built last session, blocked on red CI all along. Merged the moment CI was real.

- `frontend/lib/utils/attachment_picker_{stub,web}.dart` — `pickAttachmentFileAt({left, top, width, height, accept})`
  creates an `input[type=file]` positioned `fixed` at the paperclip's rect
  (`opacity:0`, `zIndex:-1`, `pointerEvents:none`), removed on change/cancel/error.
  `chat_action_tiles.dart` wraps the tile in a `Builder` so `tileContext.findRenderObject()`
  gives `localToGlobal(Offset.zero)` + `size`. `kIsWeb` only; off-web keeps `FilePicker`.
- **Why:** `file_picker`'s hidden input has no layout rect and its `.click()` is not
  tied to a DOM interaction, so Safari has nothing to anchor the popover to and
  centres it mid-screen (owner screenshot).
- Verified: analyze clean, **1315 passed / 10 skipped**, CI **4/4**, live in-app
  browser E2E proving the input lands at the tile's exact rect
  (`left:216px top:788px 40×40`), correct accept list, image staged,
  `leftover positioned inputs: 0`.
- Release: bump `c7c2d0e`, built from `C:/tmp/fp-anchor` (config present),
  **Giphy key verified in the bundle before publish** (1 occurrence — the new
  standing rule from 0.1.15's incident), manual staged publish (exit-21 workaround,
  10th time), **smoke 5/5**, and local↔remote `main.dart.js` md5 identical
  (`bae5fc6d8a69d665b065d03bb11eb426`) with the key present in the LIVE bundle.

**⏳ STILL OWED — the only real verification of this fix:** owner must confirm on
his iPhone that Photo Library / Take Photo or Video / Choose File now appears **at
the paperclip**, not mid-screen. **Desktop Chrome cannot reproduce popover
anchoring at all** — neither can any test.

---

## Traps paid or confirmed this session

- `/actions/runs/<id>/timing` → `total_ms: 0`. Compute billable minutes from job
  `started_at`/`completed_at` instead.
- A `404` from an authenticated endpoint proves nothing on its own. Distinguish
  "rejected" from "route absent" by making the *same URL shape* succeed with a
  known-good credential.
- `gh run rerun <id>` returns "cannot be rerun; This workflow is already running"
  when a rerun is already in flight — that is success, not failure.
- The Python kernel hangs on `subprocess` calls to `ssh`/`git show` with large
  output; write a `.py` file and run it through `bash` instead.
- Standing: after every web deploy, fully close + reopen the PWA. **Never uninstall
  or clear site data — that kills the Signal keys.**
