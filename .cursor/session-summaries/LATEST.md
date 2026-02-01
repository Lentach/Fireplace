# Ostatnia sesja (najnowsze podsumowanie)

**Data:** 2026-02-01  
**Pełne podsumowanie:** [2026-02-01-session.md](2026-02-01-session.md)

## Skrót
- **Light Mode Color Renovation:** Nowa paleta neutralna (Slack-style), fiolet #4A154B zamiast złota, czytelne nazwy. Wszystkie ekrany theme-aware. Plan: docs/plans/2026-02-01-light-mode-color-renovation.md
- Migracja avatarów do Cloudinary; AvatarCircle obsługuje pełne URL
- **Theme:** domyślny dark, RpgTheme.themeDataLight, main theme/darkTheme, Settings "Theme" (System/Light/Dark)
- **Active status + zielone kółko:** activeStatus w JWT, isOnline w friendsList/conversationsList, green dot gdy activeStatus && isOnline
- Wymagane zmienne: `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`
