---
description: Use when touching the chat composer, attachment picker, file_picker/web_file_input, media/video/voice/image messages, the iOS composer viewport pin, or anything keyboard-adjacent in the chat screen.
condition: ".*"
scope: "tool:edit(frontend/lib/widgets/chat_input_bar*), tool:write(frontend/lib/widgets/chat_input_bar*), tool:edit(frontend/lib/widgets/composer*), tool:write(frontend/lib/widgets/composer*), tool:edit(frontend/lib/widgets/chat_action_tiles.dart), tool:write(frontend/lib/widgets/chat_action_tiles.dart), tool:edit(frontend/lib/utils/web_file_input.dart), tool:write(frontend/lib/utils/web_file_input.dart), tool:edit(frontend/lib/widgets/message/**), tool:write(frontend/lib/widgets/message/**), tool:edit(frontend/lib/services/media*), tool:write(frontend/lib/services/media*)"
---

# Composer, media, platform gotchas

Read **`frontend/docs/composer-media.md`** before the first edit (verbatim former `frontend/CLAUDE.md` §7). **2026-08-19 composer rule: nothing ships here without a green repro AND the owner's explicit OK; never `git revert 0cbf17b`.** Dependabot #174 (`file_picker` 11.0.3) is deliberately open for this reason.
