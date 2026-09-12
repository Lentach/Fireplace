---
paths:
  - "frontend/lib/**/passcode*"
  - "frontend/lib/utils/privacy_curtain*"
  - "frontend/lib/services/e2e_lock_revoker.dart"
  - "frontend/lib/services/encryption/content_key_wrap.dart"
  - "frontend/web/index.html"
---
# Passcode lock

Read **`frontend/docs/passcode-lock.md`** before the first edit (verbatim former `frontend/CLAUDE.md` §10, released 0.2.22). The attach picker is exempt from the lock (a 0 s auto-lock loses the pick); never serve a web build below `d446a9d` to a browser with the passcode ON.
