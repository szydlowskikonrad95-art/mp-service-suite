# Raport dostępności (WCAG 2.1 AA) — MP Service Suite

**Data badania:** 2026-07-28 · **Wersja:** 1.0.3

Ten dokument mówi, czy ekrany, które widzi **Twój klient**, dają się obsłużyć osobom
z niepełnosprawnościami — i czym to sprawdziliśmy. Nie jest to deklaracja: badanie
**możesz powtórzyć u siebie** poleceniem podanym na końcu.

## Jak badaliśmy

- **Narzędzie:** `axe-core` — otwarty, powszechnie używany silnik testów dostępności.
- **Zakres reguł:** WCAG 2.1, poziomy **A i AA**.
- **Sposób:** badanie na **żywej stronie w prawdziwej przeglądarce**, na działającej
  instalacji WordPressa z kompletem trzech wtyczek — nie na samym kodzie. Tylko tak
  da się sprawdzić rzeczy widoczne dopiero po wyrenderowaniu: kontrast kolorów
  i pełne reguły ARIA.
- Uzupełnia to testy w naszym systemie ciągłej kontroli, które przy każdej zmianie
  pilnują etykiet pól, nazw przycisków, komunikatów dla czytników ekranu
  i unikalności identyfikatorów.

## Wynik

| Ekran | Reguł zdanych | Naruszenia |
|---|---|---|
| Formularz zgłoszenia (publiczny) | 20 | **0** |
| Panel klienta — przed zalogowaniem | 15 | **0** |
| Panel klienta — po zalogowaniu (dane osobowe, historia sprawy) | 16 | **0** |

**Zero naruszeń WCAG 2.1 AA na wszystkich ekranach, które dostarczamy.**

Wcześniejsze badanie (22 lipca) wykazało dwa problemy z kontrastem tekstu w panelu
klienta — zbyt jasny szary przy komunikacie „Brak wiadomości" i zbyt jasna zieleń przy
informacji o zamkniętej sprawie. **Oba zostały naprawione**: kolory ustawione wprost
w kodzie zastąpiono jedną, kontrastową paletą w arkuszu stylów. Powyższy wynik pochodzi
z badania po tej poprawce.

## Co jest poza naszym zakresem

Dostępność **motywu Twojej strony** (nagłówek, menu, stopka) zależy od motywu, nie od
naszych wtyczek — jeśli jest w nim problem, zobaczysz go także na stronach bez naszego
formularza. Chętnie wskażemy, co poprawić, ale nie zmieniamy cudzego motywu bez ustaleń.

## Jak powtórzyć to badanie u siebie

```bash
npm i axe-core
MP_BASE=https://twoja-strona.pl \
AXE=./node_modules/axe-core/axe.min.js \
python3 testy/a11y/audyt-axe.py
```

Skrypt sprawdza te same trzy ekrany i kończy się błędem, jeśli znajdzie choć jedno
naruszenie — możesz go wpiąć do własnych testów po każdej zmianie motywu.
