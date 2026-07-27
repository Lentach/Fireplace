# User card / profile rework (D1 Telegram Full-Bleed) + 5 bug root-causes

**Date:** 2026-07-15 (branch `feat/user-card-rework`, 0.0.120, PR pending merge)

## What was done
Two-stage rework of the user card (other-user + self "My Profile"), owner-accepted direction D1 "Telegram Full-Bleed" from rendered round-1 mockups (`docs/design/user-card-rework/round1/index.html`).

### Bug diagnosis (all file:line refs = pre-rework master)
| # | Bug | Root cause | Fix |
|---|---|---|---|
| 1 | Gallery swipe dead | `user_card_screen.dart:497` — full-bleed scrim `DecoratedBox` ABOVE the `PageView` in the hero Stack; `BoxDecoration.hitTest` returns true for bare rects, so it absorbed every pointer. Indicator read `photos.length` so it rendered anyway. | `IgnorePointer` around the scrim; `PageController` hoisted to screen state (flutter/flutter#41157). Proven by browser touch-swipe before/after. |
| 2 | Set-main/delete untestable | Two layers: (a) unreachable because of bug 1; (b) once reachable, **`api_service.dart` setPrimaryProfilePhoto rejected the response**: it required status 200 but Nest returns **201** for POST — the successful response was thrown away, and the sheet swallowed the exception silently. | Accept 200/201; all card profile actions now surface failures via `_runProfileAction` → top snackbar. Verified end-to-end vs live docker backend (set-main reorders + pager jumps to main; deleting viewed photo reveals the remaining photo). |
| 3 | Keyboard shoves screen on About edit | Centered `GlassDialog` with autofocus TextField mid-screen — iOS WebKit pans the page to reveal covered inputs (`frontend/CLAUDE.md` §7 inset trap). | Replaced with top-anchored full-screen `EditAboutScreen` (field near top → WebKit never pans). Needs one device confirmation on iOS PWA. |
| 4 | Nav bounces to Chats after save/delete | `user_card_screen.dart:82,90,135,201` — post-action `Navigator.pop()` calls popped the CARD (refresh-by-exit hack, because `UserCardVisualData` was a static snapshot). | Self card now derives data live from `AuthProvider` (watch); all pops removed; regression tests pin "card stays open". |
| 5 | "Stretched" hero avatar | DISPROVED as BoxFit — cover everywhere. Perceived distortion = 390px near-square crop + low-res legacy avatars upscaled (uploads were raw, no crop). | New 300px hero + square crop-at-upload step (`crop_your_image` 2.0.0, owner-approved dep) + Telegram shrink-to-circle collapse (`SliverPersistentHeader` custom delegate, photo rect+radius lerp into a 40px bar circle). |

### Design/IA changes
- D1 hero: full-bleed 300px pager, segment strip, name+handle on photo, edge scrims, ✎ (self) opens glass manage-photos sheet: "PHOTO N OF 3" + 3-slot tray (primary ring+star, `+` slot), set-main / add / delete for the VIEWED photo.
- Other-user: action tiles row (Message / Mute / Copy tag), About, Safety. No-photo variant keeps compact identity row.
- Deletions: contacts-tile "Message" TextButton (contacts_screen), chat-header three-dots (hosted only Block, which lives in card Safety).
- Wallpaper: per-conversation Default/Glyphs control REMOVED from card; global per-user setting in Settings → "Tło czatu" (`SettingsProvider.chatWallpaper`, key `chat_wallpaper_<uid>`, one-time migration from `conversation_wallpaper_<uid>:<conv>` keys — any glyphs ⇒ global glyphs). `chat_detail_screen` reads the global value.
- `uploadProfilePicture` now sends bytes on ALL platforms (crop output `XFile.fromData` has no native path).

## Key files
- `frontend/lib/screens/user_card_screen.dart` (rewritten), `avatar_crop_screen.dart` + `edit_about_screen.dart` (new), `settings_screen.dart` (+wallpaper tile), `settings_provider.dart`, `api_service.dart` (201 fix + bytes upload), `chat_detail_screen.dart`, `contacts_screen.dart`, l10n en/pl (+`flutter gen-l10n`), `pubspec.yaml` (crop_your_image ^2.0.0, 0.0.120)
- Tests: `test/screens/user_card_screen_test.dart` (pager swipe cycles; nav-stays ×3; confirmations), `test/providers/settings_wallpaper_test.dart` (migration ×5)
- Design artifacts: `docs/design/user-card-rework/{round1/index.html, library-eval.md}`; harness `test/preview/user_card_preview.dart` (`?theme=&variant=self|other|noPhoto`); planning `.planning/user-card-rework/`

## Verification
- `flutter analyze` 0 issues · `flutter test` **727 passed**.
- Rendered + screenshotted (Chrome 390×844): self/other, dark/light/teal/blue, sheet, crop screen, collapse morph.
- Live E2E vs docker backend: register → add 2 cropped photos → swipe → set-main → delete-viewed → edit About → glyphs toggle persisted (`flutter.chat_wallpaper_<uid>` in localStorage). All stayed in place, zero nav bounces.
- **DO NOT run `dart format`** on the tree (repo rule).

## Notes for next session
- PR from `feat/user-card-rework`; merge needs explicit owner OK. Deploy after merge (frontend from PC + PWA cache bust).
- Device confirmations pending (iOS PWA): About-edit keyboard (bug 3 fix), hero collapse feel, crop gesture.
- Known tradeoff: shrink-to-circle collapse engages only when content scrolls (short profiles don't collapse — Telegram behaves the same). Alternative (forced scroll extent) rejected: dead empty scroll region.
- The old per-card wallpaper l10n keys were removed; settings uses `settingsChatBackground/settingsWallpaperDefault/settingsWallpaperGlyphs`.
