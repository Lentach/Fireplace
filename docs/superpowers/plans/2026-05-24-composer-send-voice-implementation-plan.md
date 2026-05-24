# Composer Trailing Send + Voice Lock-Up — Implementation Plan

> **For agentic workers:** Implement one chunk per PR/review cycle. Parent spawns **code-reviewer** after each chunk, then a fix agent if needed. Do not skip ahead.

**Specs:**
- Phase 0: `docs/superpowers/specs/2026-05-24-trailing-send-button-spec.md` → version **0.0.12**
- Phase 1: `docs/superpowers/specs/2026-05-24-voice-lock-up-spec.md` → version **0.0.13**

**Baseline version at plan time:** `0.0.12` in `frontend/pubspec.yaml` (PATCH bump on Phase 0 ship only if not already bumped at merge).

---

## File map (both phases)

| File | Phase 0 | Phase 1 |
|------|---------|---------|
| `frontend/lib/widgets/input/chat_input_bar.dart` | Trailing Stack, text Send overlay, `_send` wiring | Voice Send layer, lock mirrors, locked bar delegate |
| `frontend/lib/widgets/input/recording_controller.dart` | No change (preferred) | `_isLocked`, slide-up, locked bar, public send/cancel API |
| `frontend/lib/l10n/app_en.arb` / `app_pl.arb` | `chatComposerSend*` keys | `voiceRecordingSlideUpToLock`, locked/send voice keys |
| `frontend/test/widgets/input/chat_input_bar_trailing_send_test.dart` | New — trailing send tests | Extend — locked + draft cases |
| `frontend/test/widgets/input/recording_controller_lock_test.dart` | — | New — lock gesture tests |
| `CLAUDE.md` | Composer bullet + ChatInputBar gotcha | Hold-to-record + lock-up bullet |
| `frontend/pubspec.yaml` | Confirm `0.0.12` at Phase 0 merge | Bump to `0.0.13` at Phase 1 merge |

---

## Phase 0 (0.0.12) — Trailing text Send

### Chunk 0.1 — Trailing slot Stack scaffold

**Status:** COMPLETE

**Goal:** Introduce 48×48 `Stack` with `RecordingController` always mounted and a faded text-Send overlay layer. No functional send on tap yet.

**Files touched:**
- `frontend/lib/widgets/input/chat_input_bar.dart`

**Implementation:**
- Replace bare `RecordingController` in composer `Row` with `ValueListenableBuilder<TextEditingValue>(listenable: _controller, …)`.
- Wrap trailing in `ExcludeFocus` → `SizedBox(48×48)` → `Stack(alignment: center)`.
- **Bottom layer:** `RecordingController` (unchanged props/key).
- **Top layer:** `Positioned.fill` → `IgnorePointer` → `AnimatedOpacity` (175 ms, `Curves.easeInOut`) → send icon with `_kMicRestingOffsetX` (-6) translate.
- Compute `showSend` for opacity only: `!_isRecording && !_isSendingVoice && value.text.trim().isNotEmpty`.
- **Do not** wire `onPressed` to `_send()` yet (no-op or `null` until 0.2).
- Preserve iOS WebKit focus listener, `context.select` slices, `_send()` body unchanged.

**Acceptance criteria:**
- [ ] `RecordingController` remains in widget tree in all states (empty, typing, recording).
- [ ] Typing composable text crossfades send overlay in (visual only); tap does not send.
- [ ] Mic long-press / recording bar behavior unchanged.
- [ ] No new `setState` on parent per keystroke (only trailing builder listens to controller).
- [ ] iOS viewport lock / reply focus code untouched.

**Test commands:**
```bash
cd frontend && flutter analyze lib/widgets/input/chat_input_bar.dart
cd frontend && flutter test test/widgets/input/chat_input_bar_disappearing_banner_test.dart
```

---

### Chunk 0.2 — Wire send behavior

**Status:** COMPLETE

**Goal:** Connect trailing Send to shared `_send()`; enforce hit-testing and recording precedence.

**Files touched:**
- `frontend/lib/widgets/input/chat_input_bar.dart`

**Implementation:**
- `IconButton.onPressed: showSend ? _send : null` (or equivalent).
- Confirm `showSend` false while `_isRecording` or `_isSendingVoice`.
- Ensure send layer `IgnorePointer(ignoring: !showSend)` so long-press reaches mic underlay when draft exists (spec §2.1 voice spec cross-ref).
- Verify `_send()` post-frame refocus + `showSoftKeyboardIfHidden` unchanged.

**Acceptance criteria:**
- [ ] Tap trailing Send calls `MessagingProvider.sendMessage` and clears field.
- [ ] IME Send and Ctrl/Cmd+Enter still use same `_send()`.
- [ ] Keyboard stays open after trailing send (no unfocus added).
- [ ] Whitespace-only field shows mic, send no-op via IME unchanged.
- [ ] Long-press mic works when draft text present (send overlay not hit-testable when hidden; when visible, mic underlay receives hold per stack order — verify `IgnorePointer` on overlay).

**Test commands:**
```bash
cd frontend && flutter analyze lib/widgets/input/chat_input_bar.dart
cd frontend && flutter test test/providers/messaging_provider_composer_focus_test.dart
```

---

### Chunk 0.3 — ARB, semantics, theme polish

**Status:** COMPLETE

**Goal:** Localized tooltip/semantics; `ExcludeSemantics` on hidden send layer if needed.

**Files touched:**
- `frontend/lib/l10n/app_en.arb`
- `frontend/lib/l10n/app_pl.arb`
- `frontend/lib/widgets/input/chat_input_bar.dart`
- Generated: `frontend/lib/l10n/app_localizations*.dart` (via `flutter gen-l10n`)

**Keys:**
| Key | EN | PL |
|-----|----|----|
| `chatComposerSendTooltip` | Send | Wyślij |
| `chatComposerSendSemantics` | Send message | Wyślij wiadomość |

**Acceptance criteria:**
- [ ] Send button has `Tooltip` + `Semantics` when visible.
- [ ] Hidden layer excluded from screen reader (`ExcludeSemantics` when opacity 0 if QA requires).
- [ ] Icon locked to `Icons.send_rounded`, size 22, `RpgTheme.primaryColor(context)`.

**Test commands:**
```bash
cd frontend && flutter gen-l10n
cd frontend && flutter analyze
```

---

### Chunk 0.4 — Widget tests

**Status:** COMPLETE

**Goal:** Automated regression for trailing send per spec §9.1.

**Files touched:**
- Create: `frontend/test/widgets/input/chat_input_bar_trailing_send_test.dart`
- Maybe extend: `frontend/test/widgets/input/chat_input_bar_disappearing_banner_test.dart` if structure breaks

**Tests:**
| Test | Assertion |
|------|-----------|
| Empty field | Mic visible; send faded / not hit-testable |
| Type `"hi"` | Send visible |
| Tap send | `sendMessage` called; field cleared |
| After send | Focus retained or refocused post-frame |
| Whitespace only | Send not shown |
| Widget tree | `RecordingController` always present |
| Recording | Send hidden when recording |
| `isSendingVoice` | Spinner; send hidden |

**Test commands:**
```bash
cd frontend && flutter test test/widgets/input/chat_input_bar_trailing_send_test.dart
cd frontend && flutter test test/widgets/input/chat_input_bar_disappearing_banner_test.dart
cd frontend && flutter test test/utils/web_viewport_scroll_test.dart
```

---

### Chunk 0.5 — Docs, version, graph

**Status:** COMPLETE

**Goal:** Update project memory; confirm version; refresh graph.

**Files touched:**
- `CLAUDE.md` — §1 composer bullet, §7 `ChatInputBar` gotcha (trailing Stack, never unmount RC, send paths, tests pointer)
- `frontend/pubspec.yaml` — confirm `version: 0.0.12`
- `graphify-out/` — `graphify update .`

**Acceptance criteria:**
- [ ] CLAUDE.md removes “mic-only when idle (no trailing send)” where applicable.
- [ ] Manual QA matrix §9.3 documented as release gate (iPhone PWA + Android native).
- [ ] `flutter analyze` clean on frontend.

**Test commands:**
```bash
cd frontend && flutter analyze
cd frontend && flutter test test/widgets/input/chat_input_bar_trailing_send_test.dart
graphify update .
```

---

## Phase 1 (0.0.13) — Voice lock-up

> **Do NOT start until Phase 0 merged and verified.** Reduces keyboard regression bisection difficulty.

### Chunk 1.1 — Lock state + vertical drag detection

**Status:** COMPLETE

**Files:** `recording_controller.dart`

**Goal:** `_isLocked`, `_dragStartY`, `_lockDragOffset`; `onLongPressMoveUpdate` vertical threshold (72 px); `_enterLockedMode()`; release no-op when locked.

**Acceptance criteria:**
- [ ] Slide up past threshold sets `isLocked == true`.
- [ ] `_onLongPressFinished` / pointer release skipped when locked.
- [ ] Horizontal slide-left cancel unchanged while unlocked.

**Test commands:**
```bash
cd frontend && flutter analyze lib/widgets/input/recording_controller.dart
```

---

### Chunk 1.2 — Locked recording bar UI

**Status:** NOT STARTED

**Files:** `recording_controller.dart`, `chat_input_bar.dart`

**Goal:** `buildRecordingBarLocked` (Cancel + lock label + timer); slide-up hint in unlocked bar; `onRecordingLockChanged` callback.

**Acceptance criteria:**
- [ ] Locked bar shows Cancel (44×44 min), lock icon, timer, hint text.
- [ ] Unlocked bar shows slide-up hint when vertical progress > 0.

**Test commands:**
```bash
cd frontend && flutter analyze
```

---

### Chunk 1.3 — Voice Send trailing layer + public API

**Status:** NOT STARTED

**Files:** `chat_input_bar.dart`, `recording_controller.dart`

**Goal:** Third stack layer — voice Send when `_isLocked`; `sendLockedRecording()` / `cancelLockedRecording()`; spinner precedence unchanged.

**Acceptance criteria:**
- [ ] Voice Send visible only when recording + locked.
- [ ] Text Send hidden while `_isRecording` even with draft.
- [ ] Tap voice Send calls `_stopRecording()` pipeline.

**Test commands:**
```bash
cd frontend && flutter test test/widgets/input/chat_input_bar_trailing_send_test.dart
```

---

### Chunk 1.4 — ARB + accessibility (voice lock)

**Status:** NOT STARTED

**Files:** `app_en.arb`, `app_pl.arb`, `recording_controller.dart`, `chat_input_bar.dart`

**Keys:** `voiceRecordingSlideUpToLock`, `voiceRecordingLocked`, `voiceRecordingCancelLocked`, `voiceRecordingSendVoiceTooltip`, `voiceRecordingSendVoiceSemantics`, `voiceRecordingLockedSemantics`

**Test commands:**
```bash
cd frontend && flutter gen-l10n && flutter analyze
```

---

### Chunk 1.5 — Widget tests (lock)

**Status:** NOT STARTED

**Files:** Create `recording_controller_lock_test.dart`; extend `chat_input_bar_trailing_send_test.dart`

**Test commands:**
```bash
cd frontend && flutter test test/widgets/input/recording_controller_lock_test.dart
cd frontend && flutter test test/widgets/input/chat_input_bar_trailing_send_test.dart
cd frontend && flutter test test/widgets/input/recording_controller_test.dart
```

---

### Chunk 1.6 — CLAUDE.md, version 0.0.13, manual QA gate

**Status:** NOT STARTED

**Files:** `CLAUDE.md`, `frontend/pubspec.yaml` → `0.0.13`, graphify

**Test commands:**
```bash
cd frontend && flutter analyze
graphify update .
```

---

## CI regression bundle (run before Phase 0 / Phase 1 merge)

```bash
cd frontend && flutter analyze
cd frontend && flutter test test/widgets/input/chat_input_bar_trailing_send_test.dart
cd frontend && flutter test test/providers/messaging_provider_composer_focus_test.dart
cd frontend && flutter test test/utils/web_viewport_scroll_test.dart
cd frontend && flutter test test/widgets/input/chat_input_bar_disappearing_banner_test.dart
```

**Manual gates:**
- Phase 0: iPhone Safari PWA — type → trailing send ×5, IME send ×5, reply focus (spec §9.3).
- Phase 1: iPhone PWA lock → Send/Cancel; Android native lock + draft preservation (spec §11.3).
