# Light Mode Color Renovation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Renovate light mode with modern neutral palette (Slack-inspired): soft grays, single purple accent (#4A154B), high readability. Dark mode unchanged.

**Architecture:** Replace hardcoded RpgTheme colors with Theme.of(context).brightness-aware logic. New light palette in rpg_theme.dart; all affected widgets use theme colors or resolve colors via brightness.

**Tech Stack:** Flutter, Provider, Material Theme

---

## Summary of Design Decisions (from brainstorming)

- **Accent:** Purple #4A154B (Slack purple)
- **Backgrounds:** #F4F5F7 main, #FFFFFF sidebar/cards, #FAFBFC chat area
- **Text:** #1D1C1D primary, #616061 secondary, #8B8A8B muted
- **Borders:** #E8EAED
- **Active tile:** #E8E4EC
- **Gold:** Used ONLY in dark mode; not in light mode

---

### Task 1: Update RpgTheme with new light palette

**Files:**
- Modify: `frontend/lib/theme/rpg_theme.dart`

**Step 1: Add new light palette constants**

Add after existing light constants (around line 47):

```dart
// Light mode - modern neutral (Slack-inspired)
static const Color primaryLight = Color(0xFF4A154B);
static const Color primaryLightHover = Color(0xFF611F69);
static const Color backgroundLightMain = Color(0xFFF4F5F7);
static const Color surfaceLight = Color(0xFFFFFFFF);
static const Color chatAreaBgLight = Color(0xFFFAFBFC);
static const Color textPrimaryLight = Color(0xFF1D1C1D);
static const Color textSecondaryLight = Color(0xFF616061);
static const Color textMutedLight = Color(0xFF8B8A8B);
static const Color borderLight = Color(0xFFE8EAED);
static const Color activeTileBgLight = Color(0xFFE8E4EC);
static const Color theirMsgBgLight = Color(0xFFE8E4EC);
static const Color mineMsgBgLight = Color(0xFF4A154B);
```

**Step 2: Update themeDataLight to use new colors**

Replace `themeDataLight` (lines 156-246):
- scaffoldBackgroundColor: `backgroundLightMain`
- colorScheme.primary: `primaryLight` (not gold)
- surface: `surfaceLight`
- onSurface: `textPrimaryLight`
- appBarTheme.titleTextStyle color: `primaryLight`
- inputDecorationTheme focusedBorder: `primaryLight`
- elevatedButtonTheme: backgroundColor `primaryLight`, foregroundColor white
- textTheme: bodyLarge/bodyMedium color `textPrimaryLight`, bodySmall `textSecondaryLight`, titleLarge color `primaryLight`
- Remove all references to `gold` in light theme

**Step 3: Add helper method**

```dart
static bool isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

static Color primaryColor(BuildContext context) =>
    isDark(context) ? gold : primaryLight;

static Color surfaceColor(BuildContext context) =>
    isDark(context) ? boxBg : surfaceLight;
```

**Step 4: Verify**

Run: `cd frontend && flutter analyze lib/theme/rpg_theme.dart`
Expected: No issues

---

### Task 2: Make ConversationTile theme-aware

**Files:**
- Modify: `frontend/lib/widgets/conversation_tile.dart`

**Step 1: Replace hardcoded colors**

- Line 37: `isActive ? RpgTheme.activeTabBg` → use `Theme.of(context).colorScheme` or `isDark ? activeTabBg : activeTileBgLight`
- Line 41: `RpgTheme.purple` → `primaryColor(context)` for splashColor
- Lines 62-66: `Colors.white` for displayName → `Theme.of(context).colorScheme.onSurface` or `isDark ? textColor : textPrimaryLight`
- Lines 76: `RpgTheme.mutedText` → `isDark ? mutedText : textSecondaryLight`
- Lines 94: `RpgTheme.timeColor` → `isDark ? timeColor : textSecondaryLight`

Use `final isDark = RpgTheme.isDark(context);` at start of build.

**Step 2: Verify**

Run: `cd frontend && flutter analyze lib/widgets/conversation_tile.dart`
Expected: No issues

---

### Task 3: Make ConversationsScreen theme-aware

**Files:**
- Modify: `frontend/lib/screens/conversations_screen.dart`

**Step 1: Desktop sidebar header (lines 194-262)**

- Container decoration color: `RpgTheme.boxBg` → `Theme.of(context).colorScheme.surface`
- Border color: `RpgTheme.convItemBorder` → `isDark ? convItemBorder : borderLight`
- Text 'RPG CHAT' color: `RpgTheme.gold` → `Theme.of(context).colorScheme.primary` (will be primaryLight in light mode)
- Icon colors: `RpgTheme.purple` → `Theme.of(context).colorScheme.primary` for light mode consistency
- logoutRed stays (red is universal)

**Step 2: Mobile AppBar**

- AppBar uses Theme; ensure title uses `Theme.of(context).colorScheme.primary`
- Replace `RpgTheme.pressStart2P(color: RpgTheme.gold)` with color from colorScheme.primary

**Step 3: Placeholder "Select a conversation" (lines 273-282)**

- Icon and Text color: `RpgTheme.mutedText` → `Theme.of(context).colorScheme.onSurfaceVariant` or `textMutedLight` when light

**Step 4: Empty state "No conversations" (lines 297-313)**

- Same: use theme-aware muted color

**Step 5: Delete dialog (lines 74-105)**

- backgroundColor: `RpgTheme.boxBg` → `Theme.of(context).colorScheme.surface`
- title color: `RpgTheme.gold` → `Theme.of(context).colorScheme.primary`
- content text: use `Theme.of(context).colorScheme.onSurface` with opacity
- Cancel button: use onSurfaceVariant
- Delete button: keep logoutRed

**Step 6: Divider (line 266)**

- `RpgTheme.convItemBorder` → theme-aware border

**Step 7: Verify**

Run: `cd frontend && flutter analyze lib/screens/conversations_screen.dart`
Expected: No issues

---

### Task 4: Make ChatDetailScreen theme-aware

**Files:**
- Modify: `frontend/lib/screens/chat_detail_screen.dart`

**Step 1: Read file and identify hardcoded colors**

Grep for RpgTheme, boxBg, convItemBorder, mutedText.

**Step 2: Header bar (around lines 178-183)**

- backgroundColor: theme-aware surface
- border: theme-aware border color

**Step 3: Placeholder / empty states**

- mutedText → theme-aware secondary/muted

**Step 4: Verify**

Run: `cd frontend && flutter analyze lib/screens/chat_detail_screen.dart`
Expected: No issues

---

### Task 5: Make ChatInputBar theme-aware

**Files:**
- Modify: `frontend/lib/widgets/chat_input_bar.dart`

**Step 1: Container background and border**

- color: `RpgTheme.boxBg` → `Theme.of(context).colorScheme.surface`
- border: theme-aware

**Step 2: Input decoration**

- focusedBorder: `primaryLight` in light mode
- send button: `RpgTheme.purple` → primaryColor(context)
- send icon when disabled: textMutedLight in light

**Step 3: Verify**

Run: `cd frontend && flutter analyze lib/widgets/chat_input_bar.dart`
Expected: No issues

---

### Task 6: Make ChatMessageBubble theme-aware

**Files:**
- Modify: `frontend/lib/widgets/chat_message_bubble.dart`

**Step 1: Bubble colors**

- isMine: `RpgTheme.gold` → in light use `mineMsgBgLight` (#4A154B), in dark keep gold
- !isMine: `RpgTheme.purple` → in light use `theirMsgBgLight` (#E8E4EC), in dark keep purple
- Text color: isMine in light = white; !isMine in light = textPrimaryLight

**Step 2: Verify**

Run: `cd frontend && flutter analyze lib/widgets/chat_message_bubble.dart`
Expected: No issues

---

### Task 7: Make AvatarCircle gradient theme-aware

**Files:**
- Modify: `frontend/lib/widgets/avatar_circle.dart`

**Step 1: Fallback gradient when no profile picture**

- Dark: keep purple→gold
- Light: use primaryLight→primaryLightHover or a softer purple gradient

**Step 2: Verify**

Run: `cd frontend && flutter analyze lib/widgets/avatar_circle.dart`
Expected: No issues

---

### Task 8: Make SettingsScreen theme-aware

**Files:**
- Modify: `frontend/lib/screens/settings_screen.dart`

**Step 1: Replace RpgTheme.purple, RpgTheme.gold, RpgTheme.textColor, RpgTheme.mutedText**

Use `Theme.of(context).colorScheme` and `RpgTheme.primaryColor(context)` where appropriate.

**Step 2: Verify**

Run: `cd frontend && flutter analyze lib/screens/settings_screen.dart`
Expected: No issues

---

### Task 9: Make dialogs theme-aware

**Files:**
- Modify: `frontend/lib/widgets/dialogs/reset_password_dialog.dart`
- Modify: `frontend/lib/widgets/dialogs/delete_account_dialog.dart`
- Modify: `frontend/lib/widgets/dialogs/profile_picture_dialog.dart`

**Step 1: Each dialog**

- backgroundColor: Theme.of(context).colorScheme.surface
- title/accent colors: colorScheme.primary
- text colors: colorScheme.onSurface, onSurfaceVariant

**Step 2: Verify**

Run: `cd frontend && flutter analyze lib/widgets/dialogs/`
Expected: No issues

---

### Task 10: Make AuthScreen, FriendRequestsScreen, NewChatScreen theme-aware

**Files:**
- Modify: `frontend/lib/screens/auth_screen.dart`
- Modify: `frontend/lib/screens/friend_requests_screen.dart`
- Modify: `frontend/lib/screens/new_chat_screen.dart`

**Step 1: Replace hardcoded RpgTheme colors**

Use theme-aware colors for each screen.

**Step 2: Verify**

Run: `cd frontend && flutter analyze lib/screens/`
Expected: No issues

---

### Task 11: Fix remaining widgets (MessageDateSeparator, AuthForm)

**Files:**
- Modify: `frontend/lib/widgets/message_date_separator.dart`
- Modify: `frontend/lib/widgets/auth_form.dart`

**Step 1: Use theme-aware colors**

**Step 2: Verify**

Run: `cd frontend && flutter analyze lib/`
Expected: No issues

---

### Task 12: Manual verification and CLAUDE.md update

**Step 1: Run app in light mode**

```bash
cd frontend && flutter run -d chrome
```

Switch to light theme in Settings. Verify:
- Sidebar header same color as rest
- Usernames clearly visible
- No harsh gold
- Overall eye-friendly, modern look

**Step 2: Update CLAUDE.md**

Add section under RECENT CHANGE describing light mode renovation (palette, files changed).

**Step 3: Update session summary**

Create/update `.cursor/session-summaries/2026-02-01-session.md` with light mode work.

---

## Execution Checklist

- [ ] Task 1: RpgTheme
- [ ] Task 2: ConversationTile
- [ ] Task 3: ConversationsScreen
- [ ] Task 4: ChatDetailScreen
- [ ] Task 5: ChatInputBar
- [ ] Task 6: ChatMessageBubble
- [ ] Task 7: AvatarCircle
- [ ] Task 8: SettingsScreen
- [ ] Task 9: Dialogs
- [ ] Task 10: Auth, FriendRequests, NewChat
- [ ] Task 11: MessageDateSeparator, AuthForm
- [ ] Task 12: Manual verification + docs
