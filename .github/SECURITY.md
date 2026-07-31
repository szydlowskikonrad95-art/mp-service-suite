# Zgłaszanie problemów bezpieczeństwa

Jeśli znalazłeś w tym systemie lukę bezpieczeństwa — **nie zakładaj publicznego zgłoszenia**.
Publiczny opis luki daje przewagę osobie, która chciałaby ją wykorzystać, zanim zdąży powstać
poprawka.

## Jak zgłosić

Napisz bezpośrednio do właściciela repozytorium (kontakt w profilu konta) albo skorzystaj
z prywatnego zgłaszania luk na GitHubie: zakładka **Security → Report a vulnerability**.

W zgłoszeniu przydadzą się:

- której wtyczki i wersji dotyczy (`Wtyczki → Zainstalowane` pokazuje numery),
- co dokładnie się dzieje i jak to powtórzyć,
- czego to dotyczy: danych osobowych, uprawnień, załączników, poczty czy czegoś innego.

## Czego dotyczy ta polityka

Trzy wtyczki wchodzące w skład tej paczki: **MP Service Intake**, **MP Warranty & Serial
Registry** i **MP Workflow Automator**. Poza zakresem są: sam WordPress, motyw strony, inne
wtyczki oraz konfiguracja serwera — te zgłasza się ich dostawcom.

## Co system robi dla bezpieczeństwa

Pełny opis zabezpieczeń, przyjętych granic i **rzeczy świadomie pozostawionych poza zakresem**
znajduje się w dokumentacji technicznej: [`dokumentacja-techniczna/SECURITY.md`](../dokumentacja-techniczna/SECURITY.md).
Opisane są tam między innymi: uprawnienia ról, ochrona formularza publicznego wraz z progami
limitów, przyjmowanie załączników, obsługa danych osobowych (RODO) oraz to, czego kontrole
automatyczne **nie** sprawdzają.
