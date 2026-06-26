# Fireplace Frontend — Production-Readiness Review: Progress Tracker

- **Reviewed tree:** branch `feat/message-editing` @ `814c820` (latest frontend; message-editing
  delivered). Docs committed on branch `review/frontend-prod-readiness` (never master).
- **Scope:** full deep read of EVERY frontend file — `frontend/lib/**` (184 Dart files, ~27.8k LOC
  incl. ~2.8k generated l10n), `frontend/web/**` (SW + manifest + index + icons), `frontend/test/**`
  (79 files, ~9.9k LOC), ARB locales, pubspec/dart-defines. Report-only.
- **Gate target:** live iOS PWA + upcoming Android native (both).
- **Method:** Phase 0 map (lead) → Phase 1 chunk deep-reads (parallel reviewers, each opens every
  file in its chunk, writes `findings/<CHUNK>.md`) → Phase 2 cross-cutting + analyze/test (lead) →
  Phase 3 synthesis; every Blocker/High independently re-verified against source by the lead.

## Chunk status

| Chunk | Area | Key files | Status | Findings |
|---|---|---|---|---|
| C1 | Bootstrap, auth, REST/session, API security | main.dart, config/*, auth_provider, api_service, auth_screen, auth_form, firebase_*, init_file_picker_* | pending | — |
| C2 | Socket / connection lifecycle | connection_provider, chat_reconnect_manager, socket_service, chat_resume_reassert | pending | — |
| C3 | E2E client crypto core | encryption_service, encryption/signal_stores, encryption_provider, e2e_envelope, decryption_failure_policy, e2e_diag_log | pending | — |
| C4 | Messaging provider (core + 5 parts) | messaging_provider + messaging/{events,actions,history,decrypt,send}, conversation_helpers, incoming_message_sound_service, message_expiry, message_edit_eligibility | pending | — |
| C5 | Conversations / friends / settings providers | conversations_provider, friends_provider, settings_provider | pending | — |
| C6 | Media pipeline (encrypt/upload/playback) | media_crypto_service, encrypted_media_upload_service, gif_service, link_preview_service, voice_audio_coordinator, audio_mime, audio_blob_url_*, gif_blob_url_*, download_utils_*, file_utils_* | pending | — |
| C7 | Push / notifications (app side) | push_service, web_push_bridge_*, push_sw_channel_*, notification_cleaner_*, unread_badge_sync, app_badge_math, badging_bridge_*, pwa_app_badge_clear, android_fcm_local_notifications, notify_conv_param_*, pending_deep_link_* | pending | — |
| C8 | Service worker + web/ + PWA + web shims | web/web-push-sw.js, web/index.html, web/manifest.json, secure_context_*, storage_persist_*, tab_visibility_*, soft_keyboard_*, web_focus_guard_*, web_keyboard_inset_*, web_viewport_scroll_*, web_ios_webkit_*, composer_paste_*, mic_permission_state_*, page_load_nonce, web_orientation_lock_*, portrait_lock_service, portrait_lock_policy, composer_probe_*, ping_sound_* | pending | — |
| C9 | Models | message_model, conversation_model, friend_request_model, user_model | pending | — |
| C10 | Chat / shell screens | chat_detail_screen, main_shell, conversations_screen, contacts_screen, add_or_invitations_screen, blocked_users_screen | pending | — |
| C11 | Composer / input widgets | widgets/input/* (chat_input_bar, edit_preview_bar, recording_controller, composer_attachment_*, attachment_handler, recording_waveform, chat_composer_viewport, composer_diagnostics_overlay, focus_guard_area, reply_preview_bar), chat_input_bar shim, scroll_to_message_helper, reply_preview_helper | pending | — |
| C12 | Message rendering + audio widgets | widgets/message/* (16), widgets/audio/* (5), chat_message_bubble + voice_message_bubble shims, conversation_tile, message_swipe_wrapper, ping_effect_overlay, hearth_fade_arc, message_date_separator, pinned_banner_visibility | pending | — |
| C13 | Settings / privacy / dialogs / misc widgets | settings_screen, privacy_safety_screen, widgets/dialogs/*, top_snackbar, avatar_circle, anti_quantum_note_dialog, gif_picker_sheet, disappearing_timer_sheet, chat_action_tiles, main_tab_screen_header, chat_background_pattern, portrait_required_overlay, portrait_lock_shell | pending | — |
| C14 | Theme + i18n + build/release | theme/rpg_theme, theme/app_scroll_behavior, l10n/app_en.arb, l10n/app_pl.arb (coverage diff), pubspec.yaml, dart-define wiring (deploy-web.ps1, scripts/version_dart_defines.ps1), constants/app_constants | pending | — |
| C15 | Tests + analyze + flutter test (lead-run) | frontend/test/** coverage map; `flutter analyze`; `flutter test` | pending | — |

## Cross-cutting passes (Phase 2, lead)
- [ ] Socket reconnect lifecycle end-to-end (connect/disconnect/reconnect/resume/zombie)
- [ ] Optimistic send → reconciliation (tempId → messageSent → real; failure marking; idempotency)
- [ ] E2E end-to-end on client (key gen → session → encrypt → send → decrypt → cache → reload)
- [ ] Provider disposal / listener-leak audit (all 7 providers + controllers)
- [ ] Web-vs-native conditional-import correctness (every stub/io/web triple resolves + behaves)
- [ ] SW ↔ app messaging (push → SW → page channel → navigation/badge/tray)

## Coverage statement
_(filled at the end — must state "100% of frontend chunks reviewed" or list deferred areas + why)_
