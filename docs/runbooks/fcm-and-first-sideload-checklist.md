# Owner checklist — FCM enable + first Android sideload (step by step)

Written 2026-08-04. Do the parts IN ORDER. Each part ends with a verification —
do not continue past a failed check. Companion doc: `android-release.md`
(gates, keystore, migration wording).

Prerequisites: the dev PC, SSH access to the VM (`ubuntu@51.68.138.13`), the
Firebase console login for the Fireplace project, and **an Android phone**
(your iPhone cannot run the APK — any Android 8+ device works, a friend's is
fine for the smoke).

---

## Part 0 — Keystore backup (5 minutes, DO THIS FIRST)

Why first: the moment one APK is installed anywhere, losing
`fireplace-release.jks` means that install can never be updated again — the
user's only path is uninstall, which destroys their Signal keys and history.

1. On the PC, in PowerShell at the repo root:
   ```powershell
   Get-FileHash frontend/android/keystore/fireplace-release.jks -Algorithm SHA256
   ```
   Write the hash down (password manager note is fine).
2. Copy `frontend/android/keystore/fireplace-release.jks` to TWO places that
   are not this PC and not each other's failure domain:
   - encrypted attachment in your password manager, AND
   - a USB stick / external drive kept offline.
3. Store the keystore password + key password as password-manager FIELDS —
   never in the same place as the file copy (`key.properties` is plaintext).
4. Verify EACH copy by re-hashing it:
   ```powershell
   Get-FileHash <path-to-copy> -Algorithm SHA256   # must equal step 1
   ```
   A backup you have not read back is a guess.

✅ Done when: both copies hash identical to the original.

---

## Part 1 — `FIREBASE_SERVICE_ACCOUNT` on the VM

⚠️ Heads-up before you start: step 5 runs `./deploy-backend.sh`, which pulls
master — this deploy SHIPS the reviewed §2 delete-for-me hard-delete fix and
stamps `APP_VERSION 0.1.8`. That is intended. It does NOT touch the frontend,
so the ⛔ B2b web gate is unaffected.

1. **Get the key.** Firebase console → gear icon → *Project settings* →
   *Service accounts* tab → button *Generate new private key* → Generate.
   A JSON file downloads (e.g. `fireplace-xxxxx-firebase-adminsdk-....json`).
   This file is a full server credential — treat it like a password.
2. **Copy it to the VM** (PowerShell on the PC, from your Downloads folder):
   ```powershell
   scp .\fireplace-*-firebase-adminsdk-*.json ubuntu@51.68.138.13:~/sa.json
   ```
3. **Append it to `.env` as ONE single-quoted line.** SSH in and run:
   ```bash
   ssh ubuntu@51.68.138.13
   cd ~/fireplace
   cp .env .env.bak-$(date +%F)            # rollback point
   printf "FIREBASE_SERVICE_ACCOUNT='%s'\n" \
     "$(python3 -c "import json;print(json.dumps(json.load(open('/home/ubuntu/sa.json'))))")" >> .env
   tail -c 300 .env                        # eyeball: starts with FIREBASE_SERVICE_ACCOUNT='{"type": ...
   ```
   Why single quotes: docker compose interpolates `.env`; single quotes keep
   the JSON (double quotes, literal `\n` inside `private_key`) verbatim, and
   the backend does `JSON.parse()` on the whole value.
4. **Delete the loose key files** (the `.env` copy is now the working secret):
   ```bash
   rm ~/sa.json
   ```
   and on the PC: delete the JSON from Downloads (and from the Recycle Bin).
5. **Deploy the backend:**
   ```bash
   cd ~/fireplace && ./deploy-backend.sh
   ```
6. **Verify:**
   ```bash
   docker compose -f docker-compose.prod.yml logs backend | grep -i firebase
   ```
   Must show `Firebase Admin initialized`.
   - Still `FIREBASE_SERVICE_ACCOUNT not set` → the `.env` line didn't take
     (check step 3 output).
   - `Firebase Admin init failed` → the JSON got mangled; redo step 3 from
     the `.env.bak` (`cp .env.bak-<date> .env` and start over).

✅ Done when: the boot log says `Firebase Admin initialized`. **This is NOT
the real verification** — that's Part 3, a push to a real device.

---

## Part 2 — Sideload the APK on an Android phone

The built artifact (all gates passed 2026-08-04):

```
frontend/build/app/outputs/flutter-apk/app-release.apk   (84 MB)
version 0.1.8 (6762a00) · versionCode 10008
SHA256  62baf8ff5bbb4bc433893a064215f84400e7ccbea34bef83ea30e6056fbe0035
```

1. Transfer `app-release.apk` to the Android phone (USB cable, or upload to
   Drive and download on the phone).
2. On the phone: open the APK from Files → Android asks to allow installs
   from that app → allow → Install. (Play Protect may warn about an unknown
   developer — that's expected for a sideload; tap *Install anyway*.)
3. Open Fireplace and **REGISTER A FRESH TEST ACCOUNT** for the smoke.
   Do NOT log in with your main account yet — two live devices on one account
   flip-flop the identity epoch on every reconnect (see `android-release.md`
   §migration). Your main account migration, if ever, follows the exact
   wording in that runbook.

✅ Done when: test account registered, conversations screen loads.

---

## Part 3 — REAL push verification (the actual FCM test)

1. On the phone: friend the test account with one of your existing accounts
   (from your iPhone PWA) and exchange one message each way — confirms E2E
   PreKey (`3:`) + whisper (`2:`) round trip on the APK.
2. **Kill the app**: recent-apps → swipe Fireplace away. Leave the phone
   locked, screen off.
3. From the PWA account, send the test account a message.
4. Within ~seconds the phone must show a Fireplace notification
   (generic title by design — FCM payloads are content-free wake-ups).
5. Tap it → the app must open **into the right conversation**.

✅ Done when: notification arrives with the app killed AND the tap routes to
the correct chat. This single test proves the whole chain: VM credential →
FCM → committed `google-services.json` init → background isolate → tap
deep-link. If nothing arrives: `docker compose -f docker-compose.prod.yml
logs backend | grep -i -E "fcm|push"` on the VM and report what you see.

---

## Part 4 — Rest of the device smoke (from `android-release.md`)

Still on the test account:

1. Voice note: record, send, play, seek, replay after closing/reopening chat.
2. Image send + receive (runtime-validates the 16KB-patched webcrypto).
3. Delete-for-everyone one message; set a disappearing timer, let one message
   expire → Privacy & Safety diags stay clean (no CONTENT_* escalations).
4. Flip-flop drill (deliberate, with the TEST account only): log the same
   test account into a desktop-browser PWA too, force reconnects on both →
   you'll see identity-changed banners (expected thrash). Log OUT of that
   PWA → it stabilizes and the round trip recovers.

✅ Done when: all four pass. The Android track is then ready for real
distribution (GitHub Release + SHA256, `android-release.md` §Distribution).

---

## Part 5 — Fingerprint-verify peers 54 and 90

For each of the two peers (from the standing `PEER_IDENTITY_CHANGED` events,
07-31 and 08-03), on YOUR iPhone PWA:

1. Open the chat → tap the identity-changed banner (or the peer's profile →
   security/fingerprint entry).
2. Read the fingerprint to the peer over a channel that is NOT Fireplace
   (call them, or in person).
3. Match → mark verified / dismiss the banner. Mismatch → STOP, do not chat,
   report it — a mismatch is what a server-in-the-middle looks like.

✅ Done when: both peers verified (or a mismatch reported immediately).

---

## What I still owe you after this

- On your next diag dump: 0.1.6 retire-rollout check (≤14 one-time
  `DUP_TERMINAL_RETIRED` for the known ids) + `CANARY_OK.ageDays`.
- When `ageDays > 7` and you give the word: master web deploy **0.1.9**
  ships B2b + the sweep diags (full close+reopen of the PWA after).
