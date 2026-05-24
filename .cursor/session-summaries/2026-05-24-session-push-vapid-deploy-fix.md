# Session summary — 2026-05-24 (push VAPID deploy fix)

## Accomplished

- Diagnosed prod push failure from VM logs: backend VAPID `BOyiyoPF…`, Flutter web build used hardcoded default `BOkbC_6t…` → Android PWA `push service error`, iOS delivery HTTP **400** on `web.push.apple.com`.
- **`deploy.sh`:** reads `WEB_PUSH_VAPID_PUBLIC_KEY` from repo `.env`, passes to `flutter build web`, fails fast if missing.
- **Backend:** treat Web Push HTTP **400** as stale subscription (auto-remove; user re-enables in Settings).
- Version **0.0.10**; `CLAUDE.md` + `production-vm-deploy.mdc` updated (VAPID + DB name `chatdb`).

## Key files

- `deploy.sh`
- `backend/src/push-notifications/push-notifications.service.ts`
- `frontend/pubspec.yaml`
- `CLAUDE.md`
- `.cursor/rules/production-vm-deploy.mdc`

## Deploy / verify (VM)

```bash
cd ~/fireplace && git pull && ./deploy.sh
cp -a frontend/build/web/. frontend-build/
curl -sS https://fireplace.ignorelist.com/version
```

On each phone (PWA): hard refresh or reinstall → Settings → enable push again → test message with app in background.

## Notes

- `FIREBASE_SERVICE_ACCOUNT not set` on VM is OK for PWA-only; native FCM disabled.
- Postgres DB is **`chatdb`**, not `fireplace`.
