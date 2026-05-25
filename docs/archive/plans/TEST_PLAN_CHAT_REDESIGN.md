# Chat Screen Redesign - End-to-End Test Plan

**Date:** 2026-02-04
**Features:** Message delivery indicators, disappearing messages, ping notifications, drawing canvas, image upload

---

## Prerequisites

### Backend
- [ ] Backend is running: `docker-compose up -d`
- [ ] Check logs: `docker logs mvp-chat-app-backend-1 --tail 50`
- [ ] Backend listening on http://localhost:3000

### Frontend
- [ ] Dependencies installed: `cd frontend && flutter pub get`
- [ ] No analysis errors: `flutter analyze` (ignore RadioListTile deprecation warnings)
- [ ] Device connected: `flutter devices` shows your device
- [ ] Run app: `flutter run` (or `flutter run -d <device-id>`)

---

## Test 1: Message Delivery Indicators

### Test 1.1: Sending Message Shows Clock Icon
**Steps:**
1. Login as User A
2. Open conversation with User B
3. Type a message and send
4. **Expected:** Message appears immediately with clock icon (⏱ SENDING)
5. **Expected:** Clock changes to single checkmark (✓ SENT) after ~1s

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 1.2: Receiving Message Shows Double Checkmark
**Steps:**
1. Keep User A logged in
2. Login as User B in another device/browser
3. User B sends message to User A
4. **Expected:** User B's message shows double checkmark (✓✓ DELIVERED)

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 1.3: Old Messages Have Delivered Status
**Steps:**
1. Refresh conversation (close and reopen)
2. **Expected:** All previously sent messages show ✓✓ DELIVERED

**Status:** [ ] PASS [ ] FAIL
**Notes:**

---

## Test 2: Disappearing Messages

### Test 2.1: Set Conversation Timer
**Steps:**
1. Open conversation
2. Tap Timer tile (bottom action tiles row)
3. Select "30 seconds"
4. Tap "Set"
5. **Expected:** Dialog closes, timer is set for this conversation

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 2.2: Message Shows Timer Countdown
**Steps:**
1. With timer set to 30 seconds, send a message
2. **Expected:** Message bubble shows timer icon and countdown (e.g., "29s", "28s", ...)
3. Wait 30 seconds
4. **Expected:** Message shows "Expired" or disappears (backend cron job runs every minute)

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 2.3: Timer Persists Per Conversation
**Steps:**
1. Set Timer to "1 minute" in conversation with User B
2. Navigate away (go to conversations list)
3. Open conversation with User C
4. **Expected:** Timer tile shows "Off" (default)
5. Set Timer to "5 minutes" in conversation with User C
6. Go back to conversation with User B
7. **Expected:** Timer still shows "1 minute"

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 2.4: Timer Turns Off
**Steps:**
1. Set Timer to any duration
2. Tap Timer tile again
3. Select "Off"
4. Send message
5. **Expected:** Message has no timer icon, no expiresAt

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 2.5: Backend Cron Job Deletes Expired Messages
**Steps:**
1. Set Timer to "30 seconds"
2. Send a message
3. Wait 1 minute (cron runs every minute)
4. Check backend logs: `docker logs mvp-chat-app-backend-1 --tail 50`
5. **Expected:** Log shows "Deleted 1 expired messages"
6. Refresh conversation (close and reopen)
7. **Expected:** Expired message is gone from list

**Status:** [ ] PASS [ ] FAIL
**Notes:**

---

## Test 3: Ping Feature

### Test 3.1: Send Ping
**Steps:**
1. Open conversation
2. Tap "Ping" tile (bottom action tiles row)
3. **Expected:** SnackBar shows "Ping sent!"
4. **Expected:** Ping message appears in chat with campaign icon and "PING!" text

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 3.2: Receive Ping - Visual Effect
**Steps:**
1. User B is logged in (separate device/browser)
2. User A sends ping to User B
3. **Expected (User B):** Orange circle with campaign icon animates (scales + fades)
4. **Expected (User B):** Ping sound plays (assets/sounds/ping.mp3)
5. **Expected (User B):** Effect disappears after ~800ms

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 3.3: Ping Message in History
**Steps:**
1. After sending/receiving ping
2. **Expected:** Ping message is visible in chat history
3. **Expected:** Shows campaign icon + "PING!" text
4. **Expected:** Has timestamp and delivery indicator (if sent by you)

**Status:** [ ] PASS [ ] FAIL
**Notes:**

---

## Test 4: Drawing Canvas

### Test 4.1: Open Drawing Canvas
**Steps:**
1. Open conversation
2. Tap "Draw" tile (bottom action tiles row)
3. **Expected:** Drawing canvas screen opens (white background)

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 4.2: Draw on Canvas
**Steps:**
1. Use finger/mouse to draw on canvas
2. **Expected:** Black strokes appear (3px width)
3. Draw multiple strokes
4. **Expected:** All strokes are visible

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 4.3: Eraser Mode
**Steps:**
1. Tap eraser icon (top right, icon changes to edit icon)
2. Draw over existing strokes
3. **Expected:** Strokes are erased (white 20px brush)
4. **Expected:** Bottom toolbar shows "Eraser mode" and "Stroke: 20px"

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 4.4: Clear Canvas
**Steps:**
1. Draw some strokes
2. Tap trash icon (top right)
3. **Expected:** All strokes are cleared, canvas is blank

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 4.5: Send Drawing (Empty Canvas)
**Steps:**
1. Clear canvas (no strokes)
2. Tap checkmark icon (top right)
3. **Expected:** SnackBar shows "Canvas is empty"
4. **Expected:** Canvas screen stays open

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 4.6: Send Drawing (Success)
**Steps:**
1. Draw some strokes
2. Tap checkmark icon (top right)
3. **Expected:** SnackBar shows "Uploading drawing..."
4. **Expected:** Canvas screen closes
5. **Expected:** SnackBar shows "Drawing sent!"
6. **Expected:** Drawing appears as image message in chat

**Status:** [ ] PASS [ ] FAIL
**Notes:**

---

## Test 5: Camera Image Upload

### Test 5.1: Open Camera
**Steps:**
1. Open conversation
2. Tap "Camera" tile (bottom action tiles row)
3. **Expected:** Camera app opens (native camera)
4. **Expected (iOS):** Camera permission dialog if first time

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 5.2: Take Photo and Upload
**Steps:**
1. Take a photo
2. Confirm/accept photo
3. **Expected:** SnackBar shows "Uploading image..."
4. **Expected:** SnackBar shows "Image sent!"
5. **Expected:** Image appears in chat

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 5.3: Cancel Camera
**Steps:**
1. Tap Camera tile
2. Cancel without taking photo
3. **Expected:** No error, no upload

**Status:** [ ] PASS [ ] FAIL
**Notes:**

---

## Test 6: Gallery Attachment (via ChatInputBar)

### Test 6.1: Open Gallery
**Steps:**
1. Open conversation
2. Tap attachment icon (📎 left side of ChatInputBar)
3. **Expected:** Gallery/photo picker opens

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 6.2: Select and Upload Image
**Steps:**
1. Select an image from gallery
2. Confirm selection
3. **Expected:** SnackBar shows "Uploading image..."
4. **Expected:** Image appears in chat

**Status:** [ ] PASS [ ] FAIL
**Notes:**

---

## Test 7: Image Message Display

### Test 7.1: Image Renders in Bubble
**Steps:**
1. Send an image (camera or drawing)
2. **Expected:** Image displays in message bubble (rounded corners)
3. **Expected:** Loading spinner appears while loading
4. **Expected:** Image fits within bubble (BoxFit.cover)

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 7.2: Image Load Error
**Steps:**
1. **Manual test:** Modify mediaUrl in database to invalid URL
2. Refresh conversation
3. **Expected:** Error message shows "[Image failed to load]" in red

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 7.3: Image with Timer
**Steps:**
1. Set Timer to "1 minute"
2. Send an image
3. **Expected:** Image message shows timer countdown (e.g., "59s")

**Status:** [ ] PASS [ ] FAIL
**Notes:**

---

## Test 8: Integration - All Features Together

### Test 8.1: Complex Workflow
**Steps:**
1. Login as User A
2. Open conversation with User B
3. Set Timer to "5 minutes"
4. Send text message → check delivery indicator
5. Send ping → check visual effect (if User B online)
6. Send drawing → check upload + display
7. Send camera image → check upload + display
8. **Expected:** All features work together without conflicts

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 8.2: Reconnection After Network Loss
**Steps:**
1. Send a message
2. Disable WiFi/network
3. Try to send another message
4. **Expected:** Message shows clock icon (SENDING)
5. Re-enable WiFi
6. **Expected:** Socket reconnects, message sends, delivery status updates

**Status:** [ ] PASS [ ] FAIL
**Notes:**

---

## Test 9: UI/UX - Chat Screen Layout

### Test 9.1: AppBar (Top Bar)
**Steps:**
1. Open conversation
2. **Expected:** Back arrow (left), username (center), avatar (right), three-dot menu (right)

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 9.2: ChatInputBar
**Steps:**
1. **Expected:** Attachment icon (left), text field, emoji button, mic/send toggle (right)
2. Type text
3. **Expected:** Mic icon changes to send icon

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 9.3: Action Tiles Row
**Steps:**
1. **Expected:** 6 tiles visible: Timer, Ping, Camera, Draw, GIF (coming soon), More (coming soon)
2. **Expected:** Horizontal scroll if tiles don't fit
3. **Expected:** Top border separates from input bar

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 9.4: Emoji Picker
**Steps:**
1. Tap emoji icon (right side of input bar)
2. **Expected:** Emoji picker appears below input
3. Select emoji
4. **Expected:** Emoji inserted into text field
5. Tap emoji icon again
6. **Expected:** Emoji picker closes

**Status:** [ ] PASS [ ] FAIL
**Notes:**

---

## Test 10: Backend Validation

### Test 10.1: Image Upload Validation - MIME Type
**Steps:**
1. **Manual test:** Try to upload .txt file via API
2. **Expected:** Backend returns 400 "Only JPEG/PNG images are allowed"

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 10.2: Image Upload Validation - File Size
**Steps:**
1. **Manual test:** Try to upload 10MB image
2. **Expected:** Backend returns 400 "File size must not exceed 5 MB"

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 10.3: CORS Headers
**Steps:**
1. Check browser console for CORS errors
2. **Expected:** No CORS errors when uploading images

**Status:** [ ] PASS [ ] FAIL
**Notes:**

---

## Test 11: Edge Cases

### Test 11.1: Open Conversation Without Active Conversation
**Steps:**
1. Don't select any conversation
2. Tap Ping tile
3. **Expected:** SnackBar shows "Open a conversation first"

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 11.2: Send Drawing Without Active Conversation
**Steps:**
1. **Manual test:** Open DrawingCanvasScreen directly without conversation
2. Draw and send
3. **Expected:** Error message "No active conversation"

**Status:** [ ] PASS [ ] FAIL
**Notes:**

### Test 11.3: Upload Image Without Recipient
**Steps:**
1. **Manual test:** Call uploadImageMessage API without recipientId
2. **Expected:** Backend returns 400 "Recipient not found"

**Status:** [ ] PASS [ ] FAIL
**Notes:**

---

## Summary

**Total Tests:** 41
**Passed:** [ ]
**Failed:** [ ]
**Skipped:** [ ]

**Critical Failures:**

**Notes:**

**Test Completed By:**
**Date:**

---

## Automated Pre-Flight Checks

Run these before manual testing:

```bash
# Backend
cd backend
npm run build  # Should succeed
docker-compose up -d
docker logs mvp-chat-app-backend-1 --tail 50  # Check for startup errors

# Frontend
cd frontend
flutter pub get
flutter analyze  # Should have 0 errors (warnings OK)
flutter test  # Should pass all unit tests
```

**Backend Build:** [ ] PASS [ ] FAIL
**Frontend Analyze:** [ ] PASS [ ] FAIL
**Frontend Tests:** [ ] PASS [ ] FAIL
