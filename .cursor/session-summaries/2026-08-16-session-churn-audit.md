# 2026-08-16 — Churn population audit (§10.1 of the consolidated handoff): storage loss confirmed for user 54 only

**NO CODE CHANGED. No deploy. Prod access read-only (nginx logs, backend logs, SELECTs).**
Executes item 1 of `2026-08-16-HANDOFF-identity-loss-consolidated.md` §10: *"Audit whether some of
the eight churns are legitimate second-device logins, not wipes."* Answer: of the **nine** dated
churn events, **4 are proven non-wipe** (76, 92, 58, 43), **3 are wipes — all user 54**, and **2 are
UNKNOWN — both user 90**.

## Verdict table — every known churn, classified

Method: for each churn login, the nginx window around it. The affirmative proof runs ONE way:
**warm HTTP cache (304s) plus a push POST updating a months-old endpoint row proves the same
long-lived container** — a wipe of the origin storage bucket cannot forge a 304, because the HTTP
cache lives outside the bucket. The converse is NOT a proof: a cold cache (200s on files no deploy
changed — `favicon.png` 485 B, `Icon-192.png` 18 483 B, the `GET /` document) only shows the HTTP
cache was empty, which a fresh context produces but which Chrome's own origin eviction plus an
independent HTTP-cache LRU eviction can also produce on a dormant profile. So cold-cache churns are
classified by *additional* evidence — an explicit logout + account switch (76/92), a Chrome major
version that differs from the user's established context (43, Chrome never downgrades) — or left
UNKNOWN (90).

| churn | user | class | evidence |
|---|---|---|---|
| 07-31 17:07 | 90 | **UNKNOWN** | dated by OTP batch-insert `17:07:51`; nginx log no longer reaches 07-31 |
| 08-03 15:51 | 54 | **SAME-CONTAINER WIPE** | login `15:50:59` (31.0.88.18, iPhone 18_5) → OTP batch `15:51:01`; then `GET /` **304**, `main.dart.js` **304**, all assets 304; push POSTs `15:51:01`/`15:51:53` updating the **2026-05-13 endpoint row**. Storage empty, HTTP cache warm, subscription alive. |
| 08-11 13:20 | 76 | **fresh/second context** (behavioral) | 37.30.58.98 Android: cold fetch at 13:20:23 (consistent with, not proof of, a fresh context), then **explicit `POST /auth/logout` 13:21:17** and an immediate login as account 92 — deliberate multi-account use of one context; nobody wipes a device and switches accounts within two minutes. |
| 08-11 13:23 | 92 | **same context, 2nd account** | same IP, no asset refetch between logins; account switch after the explicit logout. New push subscription created 13:30 (user gesture). One person (76+92), one context, two accounts. |
| 08-14 01:17 | 58 | **owner incognito** (known) | cold fetch, `canvaskit/canvaskit.js` (WebKit), iPhone OS 26_6 — the build-check account. |
| 08-14 15:31 | 90 | **UNKNOWN** | 187.13.29.35 Android Chrome/151: ALL 200 at 15:30:58 incl. `favicon` 485/`Icon-192` 18483 (unchanged by 0.1.9 — the deploy-day 200 excuse does not apply to them), `/users/me` **200**. **No push POST on boot** (Chromium's subscription is in-bucket) → that context held no subscription; new endpoint minted next morning 08-15 08:39 via user gesture. Fresh profile/device, user-cleared browsing data, and **dormant-profile Chrome eviction + independent HTTP-cache LRU** all fit; same Chrome/151 as his 08-15 row, so the version trick cannot separate devices. **Not decidable server-side.** |
| 08-14 16:38 | 54 | **SAME-CONTAINER WIPE** (already proven in the handoff §3.3) | 304s on `/users/me`+avatars, push POST updated the 05-13 row at 16:38:43. |
| 08-15 09:20 | 43 | **SECOND BROWSER/DEVICE — proven** | 194.187.72.34: full cold fetch on a non-deploy day (every asset 200), **UA = Chrome/150** while his established context (push row updated 08-14 11:47) is **Chrome/151** — Chrome never downgrades, so this is a different browser/device. No push POST. Google `GoogleAssociationService` fetched `/.well-known/assetlinks.json` at 09:19:40 mid-boot — WebAPK/install-flow fingerprint. |
| 08-15 18:23 | 54 | **WIPE, and DEEPER than 08-14's** | iPhone 18_5, warm cache (`/users/me` 304, avatars 304) — but **NO push POST at login (18:23) or at the 18:27 refresh**, unlike every prior boot of this container (08-03 ×2, 08-14; the owner's PWA POSTs on every refresh). `getSubscription()` returned null. Per retraction #10, only four things kill an iOS subscription: full website-data wipe, **web-clip removal/reinstall**, `unsubscribe()`, permission revocation. The 08-14 wipe spared the subscription; the 08-15 event did not. |

Supporting facts: an iPhone-18_5 page load exists at **08-15 17:07:16** (37.248.169.24, `GET /` 304 +
`flutter_bootstrap.js` 304 — warm cache), 76 min before 54's 18:23 login; attribution is uncertain
(several iOS 18.5 users, carrier NAT), so whether his 18:23 login followed a fresh boot or an
app left sitting open is **undetermined**. Backend audit shows him failing logins at
**08-14 22:00:19/21** (iPhone) — logged out again **5.4 h** after the 16:38 login.

**Owner-confirmed field facts (added after user interviews, same day):**
- **54 uses ONLY the Home-Screen PWA, never a Safari tab** (owner asked him directly). This kills
  any residual Safari-tab reading of the 08-15 churn: it was the PWA container, with its push
  subscription destroyed ⇒ web-clip reinstall, full website-data wipe, or an OS-level purge. Still
  unasked: did he delete/re-add the icon, and any iOS storage-full warning.
- **90 uses Chrome; owner considers "he cleared browser data" the probable story but the user does
  not remember** — stays UNKNOWN, now with a lean. He installed ~a month ago (account created
  07-20) and once lost his password and created a new account.
- Owner's takeaway: the 0.1.9 deploy is exonerated (churns predate it; confirmed here), triggers are
  device/browser-level. **The app-level defect stands regardless**: silent regeneration on the
  `absent` branch turns any environmental wipe into permanent history loss for peers — the §5.1
  guard is what makes the trigger not matter.

## What this does to the hypothesis space

1. **The CONFIRMED storage-loss population is USER 54 ALONE** (08-03 proven, 08-14 proven, 08-15
   probable — same warm-cache signature but subscription also dead). Both of 90's churns are
   UNKNOWN (07-31: log expired; 08-14: cold cache is not decidable). 58, 76, 92, 43: fresh/second
   contexts, not storage loss.
2. **Handoff §4.2 ("two engines, WebKit AND Blink, both losing the same origin") is DOWNGRADED, not
   resolved** — the Blink half is unproven: 90's churn boot no longer *evidences* a storage loss
   (it reads equally as a fresh context), so nothing forces a cross-engine mechanism. What remains
   evidence-backed is **one iPhone (iOS 18.5, Home-Screen PWA, owner
   reports low device storage) losing its container contents three times in 12 days** while the
   owner's healthy iOS 18.7 PWA loses nothing. iOS purging website data under disk pressure is a
   documented behavior class (Apple forum threads 48083/125041/125627; WebKit's own iOS 17+ claim is
   that *persistent-mode* origins are exempt — which circles back to §10.3: was persist actually
   granted in that container before the loss? The app requests it unawaited, after `initialize()`).
3. **New iOS discriminator, missed by two sessions: subscription DESTRUCTION is informative even
   though survival is not** (§4.1 table said survival proves nothing — true; but the 08-15 boot
   shows the *absence* of the boot-time push POST in the access log, and that absence separates
   "localStorage-only loss" from "whole-container/web-clip-level event" with zero client access).
4. **The §5.2 design concern is now quantified: second-device logins are the largest proven churn
   class** (4 of 9 events proven non-wipe; 90's two are unknown; 54's three are wipes). The §5.1
   guard's "bundle exists" prompt is the *common* path, not an edge case — its wording must read as
   "you signed in on a new device/browser", with the wipe case as the variant, not the reverse.

## For the next agent

- Techniques: warm-cache-plus-push-POST is the one-way proof of a same-container wipe; cold cache
  alone decides nothing (see method note). Unchanged-asset 200s beat the bundle fingerprint on
  deploy days; Chrome major version in the UA separates same-user browsers; OTP `createdAt`
  batch-inserts date pre-log-window churns to the second (54: `08-03 15:51:01`, 90: `07-31 17:07:51`).
- User 54 next contact: ask **which icon he taps** (Home Screen vs Safari) and whether he deleted /
  re-added the icon or cleared website data between 08-14 evening and 08-15 18:23 — his subscription
  died in exactly that window. Also whether iOS has shown him a storage-full warning.
- ~~The deferred password reset for 54~~ **MOOT (owner, 08-16): he logged in with his old
  password; no reset needed.** Same day the owner **authorized the §5.1 guard + §5.3 markers for
  0.1.10**, after confirming the guard moves no key material (a read-only `{exists: bool}` check
  against the public bundle the server already holds).

**Working tree after this session: docs only at audit time** (this file, in-place amendments to
handoff §4.2 and §10.1, `LATEST.md` banner + entry); owner directed COMMIT on 08-16. The 0.1.10
guard implementation follows as separate code commits.
