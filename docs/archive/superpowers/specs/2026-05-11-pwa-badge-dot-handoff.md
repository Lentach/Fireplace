# Handoff: PWA badge — liczba → kropka (indicator)

**Cel:** Zamiast pokazywać na ikonie zainstalowanej PWA **liczbę** nieprzeczytanych (`min(suma, 19)`), wystarczy **ogólny znacznik** (kropka / „jest coś nowego”), dopóki `sum(unreadCounts) > 0`; przy zerze — `clearAppBadge`.

**Dlaczego:** Na Android Chrome i tak często widać tylko kropkę; uproszczenie produktowe i prostszy kontrakt z Badging API (`setAppBadge()` bez argumentu).

---

## Pliki do zmiany (stan na 2026-05-11)

| Obszar | Ścieżka |
|--------|---------|
| Logika synchronizacji | `frontend/lib/services/unread_badge_sync.dart` — dziś `_flush()` używa `sumUnreadBadgeCounts`, `capUnreadForBadge`, `setBadgeCount(capped)`. |
| Bridge web | `frontend/lib/services/badging_bridge_web.dart` — dziś `callMethod(nav, 'setAppBadge', [cappedNonZero])`. |
| Stub nie-web | `frontend/lib/services/badging_bridge_stub.dart` — dopasować sygnaturę API bridge. |
| Math (opcjonalnie) | `frontend/lib/utils/app_badge_math.dart` — jeśli liczba nie jest już używana do badge, uprościć lub zostawić tylko `sumUnreadBadgeCounts` dla innych celów. |
| Testy | `frontend/test/utils/app_badge_math_test.dart` — zaktualizować/usunąć testy `capUnreadForBadge` jeśli funkcja znika albo zmienia znaczenie. |
| Dokumentacja | `CLAUDE.md` — sekcja PWA / badge: opisać indicator zamiast liczby. |

**Wiring:** `MainShell` tworzy `UnreadBadgeSync` w `postFrameCallback` gdy `kIsWeb` — bez zmian struktury, tylko zachowanie bridge/sync.

---

## Sugestia implementacji API bridge

- Dodać np. **`setBadgeIndicator()`** (lub zmienić semantykę `setBadgeCount`): wywołać **`navigator.setAppBadge()` z pustą listą argumentów** przez `js_util.callMethod(nav, 'setAppBadge', [])` — według MDN oznacza **generic badge** bez liczby.
- **`clearBadge()`** bez zmian (`clearAppBadge`).
- W **`UnreadBadgeSync._flush()`:** jeśli `raw > 0` i wcześniej nie ustawiono indicatora (np. flaga bool `_indicatorShown` zamiast `_lastSentCapped`), wywołać `setBadgeIndicator()`; jeśli `raw == 0`, `clearBadge()` i zresetować flagę. Uniknąć zbędnych wywołań jak dotychczas (deduplikacja stanu).

---

## Testy / weryfikacja

- `flutter test` (szczególnie `app_badge_math_test`, ewentualnie mock bridge dla `UnreadBadgeSync` jeśli dodacie testy jednostkowe).
- `flutter analyze`.
- Po zmianach: `graphify update .` (reguły workspace).

---

## Opcjonalnie później (poza tym handoffem)

- **`frontend/web/web-push-sw.js`:** przy evencie `push` wywołać ten sam wzorzec indicatora, żeby kropka pojawiała się zanim użytkownik otworzy aplikację — sprawdzić wsparcie Badging API w kontekście SW w docelowych przeglądarkach.

---

## Kontekst wcześniejszych usterek (żeby nie zepsuć)

- `ConversationsProvider.onConversationsList` **scala** `unread` z snapshotem: `prev > server ? prev : server` — nie usuwać przy pracy nad badge; dotyczy sumy `unreadCounts`, nie wyświetlanej liczby na ikonie.
