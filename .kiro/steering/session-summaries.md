---
inclusion: always
---

# Session summaries

Ten projekt utrzymuje historię pracy agenta w `.cursor/session-summaries/`. Nowe wpisy trafiają tam razem z wcześniejszymi (najnowsze to `2026-05-11-*.md`, indeks w `LATEST.md`). Nie używamy `.cursor/rules/session-summaries/` — to stary katalog, pozostawiony historycznie.

## Na START sesji

1. Przeczytaj `.cursor/session-summaries/LATEST.md`, żeby poznać kontekst ostatniej pracy.
2. W razie potrzeby sięgnij do konkretnego pliku `YYYY-MM-DD-*.md`, do którego wskazuje `LATEST.md`.

## Po każdej znaczącej zmianie

Znacząca zmiana to: nowa funkcja, bugfix, refaktor, zmiana API/środowiska/zależności, zmiana bezpieczeństwa, zmiana testów, update `CLAUDE.md`. Trywialne edycje (literówka, formatowanie jednej linii) nie wymagają osobnego summary, ale mogą być dopisane do istniejącego wpisu z tego dnia.

1. Utwórz lub zaktualizuj plik `.cursor/session-summaries/YYYY-MM-DD-session.md` z dzisiejszą datą.
   - Jeżeli w danym dniu było kilka niezależnych wątków pracy, używaj sufiksu, np. `2026-05-11-session.md`, `2026-05-11-session-bottom-insets-fix.md`.
2. W pliku opisz:
   - **Co zostało zrobione** (konkrety, nie ogólniki)
   - **Kluczowe pliki / miejsca** jakie zmieniono (ścieżki)
   - **Weryfikacja** — co zostało uruchomione/przetestowane i z jakim wynikiem
   - **Status projektu / notatki dla następnej sesji** — blokery, TODO, rzeczy do pamiętania
3. Zaktualizuj `.cursor/session-summaries/LATEST.md`:
   - Nowy wpis `**Date:** YYYY-MM-DD` i link do nowego pliku summary.
   - Poprzedni `**Date:**` przesuń na `**Previous:**`, a wcześniejsze pozycje kaskadowo na `**Earlier:**` (zgodnie z istniejącym formatem pliku).
4. Treść piszemy zgodnie z językiem istniejących wpisów — jest w nich mieszanka polskiego i angielskiego, dostosuj się do tego, co pasuje do zmiany; nazwy plików, kodu i komend zawsze po angielsku.

## Kiedy zapisać summary

- Zawsze po ukończeniu zadania, które zmieniło zachowanie projektu, przed zgłoszeniem użytkownikowi "gotowe".
- Po code review z wprowadzonymi poprawkami.
- Po rozwiązaniu incydentu/bugfixa, nawet jeśli zmiana jest mała — żeby był ślad w historii.
- Przed końcem dłuższej sesji, nawet jeśli praca nie jest zakończona — zapisz stan pośredni w summary, żeby następna sesja mogła ją podjąć.

## Format pliku summary

Przykład minimalnej struktury:

```markdown
# <krótki tytuł, 5-10 słów>

**Date:** YYYY-MM-DD

## What was done
- …

## Key files
- `path/to/file.ext` — opis zmiany
- …

## Verification
- `<komenda>` — `<wynik>`

## Notes for next session
- …
```

## Nie pomijaj tego kroku

Kolejne sesje (i inni agenci) zależą od tych notatek. Jeżeli nie zapisałeś summary po znaczącej zmianie, praca nie jest zakończona.
