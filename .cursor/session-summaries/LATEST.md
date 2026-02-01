# Ostatnia sesja (najnowsze podsumowanie)

**Data:** 2026-02-01  
**Pełne podsumowanie:** [2026-02-01-remove-active-status.md](2026-02-01-remove-active-status.md)

## Skrót
- **Remove Active Status Toggle:** Całkowicie usunięto toggle "Active Status" z ustawień. Zielone kółko = użytkownik połączony (WebSocket), szare = offline. Logika: `isOnline: onlineUsers.has(userId)` (tylko połączenie). Usunięto: kolumnę activeStatus, endpoint PATCH /users/active-status, handler updateActiveStatus, event userStatusChanged, cały kod frontendu z toggle.
- Backend: chat-conversation.service.ts, chat-friend-request.service.ts - wszystkie payload'y z `isOnline` sprawdzają `onlineUsers.has(id) && activeStatus`
- Frontend: SocketService.isConnected, settings_screen avatar fix, ChatProvider connection logging
- Wszystkie testy kompilacji przeszły pomyślnie. Manual testing wymaga restartu Docker Desktop.
- **Light Mode Color Renovation:** Nowa paleta neutralna (Slack-style), fiolet #4A154B zamiast złota, czytelne nazwy. Wszystkie ekrany theme-aware.
- Migracja avatarów do Cloudinary; AvatarCircle obsługuje pełne URL
- **Theme:** domyślny dark, RpgTheme.themeDataLight, main theme/darkTheme, Settings "Theme" (System/Light/Dark)
