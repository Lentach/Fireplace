# 🚀 START HERE - Active Status Green Dot Fix

**For the next agent:** Read this first, then execute the implementation plan.

---

## 📋 Quick Context

**Problem:** Green dot (online indicator) never shows up. Grey dot always displays, even when user is online with activeStatus ON.

**Root cause:** Backend doesn't check `user.activeStatus` when emitting `isOnline` field. Frontend Settings screen uses local toggle state instead of actual WebSocket connection.

**Solution:** 3 changes needed (backend + frontend) across 5 files.

---

## 🎯 Your Mission

Execute the implementation plan task-by-task:

**Full plan:** `docs/plans/2026-02-01-active-status-green-dot-fix.md`

**How to execute:**
1. Read the full plan: `docs/plans/2026-02-01-active-status-green-dot-fix.md`
2. Use the **executing-plans** skill (REQUIRED)
3. Execute tasks 1-8 in order
4. Test after each task
5. Commit frequently

---

## 📂 Files You'll Modify

**Backend (2 files):**
- `backend/src/chat/services/chat-conversation.service.ts` - Add `&& user.activeStatus` check
- `backend/src/chat/services/chat-friend-request.service.ts` - Add `&& user.activeStatus` check (multiple locations)

**Frontend (3 files):**
- `frontend/lib/services/socket_service.dart` - Add `isConnected` getter
- `frontend/lib/screens/settings_screen.dart` - Fix own avatar logic
- `frontend/lib/providers/chat_provider.dart` - Add logging

**Docs (2 files):**
- `CLAUDE.md` - Update Active status section
- `.cursor/session-summaries/` - Create session summary

---

## 🧪 Quick Test Plan

After implementation:
1. **Settings screen:** Toggle activeStatus → green/grey dot should change
2. **Conversations list:** Friend's dot should be green only if friend is online AND has activeStatus ON
3. **Real-time:** Toggle activeStatus in one browser → other browser sees dot change within 1-2s

---

## ⚡ Commands Quick Reference

**Backend:**
```bash
cd backend
npm run build          # Verify TypeScript compiles
npm run start:dev      # Run backend
```

**Frontend:**
```bash
cd frontend
flutter analyze        # Check for issues
flutter run -d chrome  # Run app
flutter build web --no-tree-shake-icons  # Build
```

**Git:**
```bash
git status
git add <files>
git commit -m "fix(scope): description"
git log --oneline -10
```

---

## 📚 Key Documentation

- **Architecture:** `CLAUDE.md` - Full project knowledge base
- **Latest session:** `.cursor/session-summaries/LATEST.md`
- **WebSocket events:** `CLAUDE.md` line 214-234

---

## 🎬 How to Start

**Step 1:** Read the full implementation plan:
```
Read: docs/plans/2026-02-01-active-status-green-dot-fix.md
```

**Step 2:** Use executing-plans skill:
```
"I'm executing the plan in docs/plans/2026-02-01-active-status-green-dot-fix.md"
[Use: superpowers:executing-plans skill]
```

**Step 3:** Start with Task 1 (Backend - Conversations List)

---

## ⚠️ Important Notes

1. **Test after EACH task** - Don't batch all changes without testing
2. **Backend must be running** for frontend tests to work
3. **Need 2 users logged in simultaneously** to test green dot (use 2 browser tabs/windows)
4. **Green dot logic:** `isOnline = onlineUsers.has(userId) && user.activeStatus`
5. **Commit frequently** - After each task completion

---

## ✅ Success Criteria

- [ ] Green dot shows when user online + activeStatus ON
- [ ] Grey dot shows when user offline OR activeStatus OFF
- [ ] Own avatar in Settings works correctly
- [ ] Friends' avatars in list/chat work correctly
- [ ] Real-time updates work (toggle activeStatus)
- [ ] All code builds without errors
- [ ] Documentation updated

---

## 🆘 If You Get Stuck

1. **Check CLAUDE.md** - Has all architecture details
2. **Check existing code** - Similar patterns in `onUserStatusChanged` handler (line 220-248 in chat_provider.dart)
3. **Backend logs** - Enable debug logging in NestJS to see what's emitted
4. **Frontend debug** - Use Flutter DevTools console to inspect received WebSocket events

---

## 📝 After Completion

1. Update `.cursor/session-summaries/LATEST.md` with link to your session summary
2. Update `CLAUDE.md` Active status section with final implementation details
3. Run final verification (Task 8 in plan)
4. Test all 4 scenarios from Task 6

---

**Good luck! The plan is detailed and step-by-step. Just follow it task by task.** 🚀
