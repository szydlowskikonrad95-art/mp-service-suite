#!/usr/bin/env bash
# ZYWY DOWOD (cz.1 pkt 3): „czas obslugi" znaczy TO SAMO u klienta i w eksporcie,
# a liczba sprzed tej wersji nadal jest w pliku do znalezienia.
#
# CO BYLO ZLE: produkt mial dwie podstawy czasu do tego samego pojecia —
#   * eksport CSV liczyl od ZLOZENIA (`CaseRepo::query`, pole `handling_seconds`),
#   * wpis zamykajacy pokazywany KLIENTOWI liczyl od POTWIERDZENIA
#     (`ClosingReport::handling_label`).
# Rozjazd siega okna potwierdzenia, czyli `CaseRepo::CONFIRM_WINDOW_HOURS` = 72 h.
#
# ⚠️ ZAMOWIENIE TEGO NIE ROZSTRZYGA — mowi tylko o eksporcie z czasem obslugi.
# Dlatego produkt podaje OBIE wielkosci, kazda z podstawa nazwana w naglowku, i to
# klient rozstrzyga, ktora jest dla niego „czasem obslugi". Ta kontrola pilnuje, ze
# obie sa policzone, nazwane i zgodne z tym, co widzi klient.
#
# LICZBY SA Z POMIARU NA ZYWEJ SPRAWIE (audyt 3.08, SRV/2026/0059):
#   zlozona 01:44:21 · potwierdzona 01:58:32 · zamknieta 02:03:42
#   => wiek sprawy 1161 s (0,32 h) · czas obslugi 310 s (0,09 h) · roznica 14 minut.
# Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

CSV=/tmp/mp-cz1-3-export.csv
ZLOZONA='2026-08-03 01:44:21'
POTWIERDZONA='2026-08-03 01:58:32'
ZAMKNIETA='2026-08-03 02:03:42'
WIEK=1161        # zamkniecie - zlozenie
OBSLUGA=310      # zamkniecie - potwierdzenie

COORD=$(wp user get coordcz13 --field=ID 2>/dev/null | tr -d '[:space:]')
[ -z "$COORD" ] && COORD=$(wp user create coordcz13 coordcz13@example.com --role=mp_coordinator --user_pass=x --porcelain 2>/dev/null | tr -d '[:space:]')
[ -n "$COORD" ] && ok "konto koordynatora do eksportu (ID $COORD)" || bad "brak konta koordynatora"

# ── 0. Sprawa przechodzi PELNA droge: zlozenie -> potwierdzenie -> zamkniecie ──
# Dopiero prawdziwe zamkniecie kontraktem wyzwala raport koncowy dla klienta —
# a to jego tresc porownujemy nizej z eksportem.
OUT=$(wp mp case-create --kind=reklamacja --email=cz13@example.com --name='Jan Kowalski' \
	--serial=SEK-CZ13 --document='FV/2026/13' --date='2026-05-01' --desc='podstawa czasu' 2>/dev/null)
CID=$(echo "$OUT" | grep '^case_id=' | cut -d= -f2)
NUMER=$(echo "$OUT" | grep '^case_number=' | cut -d= -f2)
TOKEN=$(echo "$OUT" | grep '^token=' | cut -d= -f2)
wp eval "MP\\Intake\\CaseRepo::verify('$TOKEN');" >/dev/null 2>&1
wp eval "apply_filters('mp_case_change_status', null, $CID, 'w analizie', 'nowe', 1, null);" >/dev/null 2>&1
wp eval "apply_filters('mp_case_change_status', null, $CID, 'zamknięte', 'w analizie', 1, null);" >/dev/null 2>&1

STATUS=$(q "SELECT status FROM wp_mp_service_cases WHERE id=$CID")
[ "$STATUS" = "zamknięte" ] && ok "sprawa $NUMER przeszla droge do zamkniecia" || bad "sprawa nie zamknieta (status=$STATUS)"

# ── 1. WPIS DLA KLIENTA mowi, OD CZEGO liczy czas ──────────────────────────
# Do 1.3.12 stalo tam samo „Czas obsługi: …" — ta sama nazwa, co w eksporcie,
# a liczone od czego innego. Czlowiek nie mial jak tego rozroznic.
# ⚠️ Tabela nazywa sie `wp_mp_messages`, a kolumna `body` — pierwsza wersja tej kontroli
# pytala o `wp_mp_case_messages`/`content`, wiec zapytanie WALILO BLEDEM i zwracalo pusto.
# Kontrola „padala" niezaleznie od produktu; przy odwrotnym warunku przechodzilaby zawsze.
# Dlatego najpierw sprawdzamy, ze raport w ogole powstal, a dopiero potem jego tresc.
RAPORTY=$(q "SELECT COUNT(*) FROM wp_mp_messages WHERE case_id=$CID AND author_type='system'")
[ "${RAPORTY:-0}" -ge 1 ] 2>/dev/null \
	&& ok "raport koncowy powstal jako wiadomosc systemowa sprawy" \
	|| bad "brak raportu koncowego — nie ma czego sprawdzac (zapytanie albo zamkniecie)"

RAPORT=$(q "SELECT COUNT(*) FROM wp_mp_messages WHERE case_id=$CID AND body LIKE '%od potwierdzenia zgłoszenia%'")
[ "${RAPORT:-0}" -ge 1 ] 2>/dev/null \
	&& ok "wpis zamykajacy widoczny dla klienta NAZYWA podstawe (od potwierdzenia)" \
	|| bad "wpis dla klienta nadal nie mowi, od czego liczy czas obslugi"

# ── 2. Znaczniki czasu jak na zmierzonej sprawie SRV/2026/0059 ─────────────
wp db query "UPDATE wp_mp_service_cases
	SET created_at='$ZLOZONA', verified_at='$POTWIERDZONA', status_changed_at='$ZAMKNIETA'
	WHERE id=$CID" >/dev/null 2>&1

# ── 3. KONTRAKT oddaje DWIE wielkosci, obie policzone poprawnie ────────────
POLA=$(wp eval --user="$COORD" '
	$szukany = "'"$NUMER"'";
	foreach ( (array) apply_filters( "mp_cases_query", null, array(), 1, 500 )["rows"] as $w ) {
		if ( ( $w["case_number"] ?? "" ) === $szukany ) {
			echo "obsluga=" . var_export( $w["handling_seconds"] ?? null, true )
				. ";wiek=" . var_export( $w["age_seconds"] ?? null, true );
		}
	}
' 2>/dev/null | tr -d '[:space:]')

echo "$POLA" | grep -q "obsluga=$OBSLUGA;" \
	&& ok "czas obslugi liczony OD POTWIERDZENIA: $OBSLUGA s ($POLA)" \
	|| bad "czas obslugi liczony ze zlej podstawy ($POLA — oczekiwane obsluga=$OBSLUGA)"

echo "$POLA" | grep -q "wiek=$WIEK" \
	&& ok "wiek sprawy liczony OD ZLOZENIA: $WIEK s — stara liczba nie przepadla" \
	|| bad "brak wieku sprawy albo zla podstawa ($POLA — oczekiwane wiek=$WIEK)"

# ── 4. EKSPORT: obie kolumny, obie nazwane, obie na TEJ SAMEJ sprawie ──────
wp eval --user="$COORD" "\$_GET['_wpnonce']=wp_create_nonce('mp_automator_export_csv'); \$_REQUEST['_wpnonce']=\$_GET['_wpnonce']; MP\\Automator\\CsvExport::handle();" >"$CSV" 2>/dev/null

head -1 "$CSV" | grep -q 'Czas obsługi od potwierdzenia (godz.)' \
	&& ok "naglowek nazywa podstawe czasu obslugi" \
	|| bad "naglowek nadal nie mowi, od czego liczy czas obslugi"

head -1 "$CSV" | grep -q 'Wiek sprawy od złożenia (godz.)' \
	&& ok "eksport ma OSOBNA kolumne wieku sprawy" \
	|| bad "brak kolumny wieku sprawy"

# Separator dziesietny zalezy od jezyka witryny (0,32 albo 0.32) — dopuszczamy oba,
# inaczej kontrola mierzylaby locale, a nie produkt.
WIERSZ=$(grep -F "$NUMER" "$CSV" | head -1)
echo "$WIERSZ" | grep -qE '0[.,]09' \
	&& ok "w wierszu sprawy stoi czas obslugi 0,09 h (od potwierdzenia)" \
	|| bad "brak czasu obslugi 0,09 w wierszu sprawy ($WIERSZ)"

echo "$WIERSZ" | grep -qE '0[.,]32' \
	&& ok "w TYM SAMYM wierszu stoi wiek sprawy 0,32 h — liczba sprzed 1.3.12 do znalezienia" \
	|| bad "stara liczba 0,32 zniknela z eksportu ($WIERSZ)"

# ── 5. ZESTAWIENIE: obie sekcje + zdanie o tym, ze to nasza interpretacja ──
grep -q 'Wiek sprawy — od złożenia zgłoszenia do zamknięcia' "$CSV" \
	&& ok "zestawienie ma osobna sekcje wieku sprawy (srednia sprzed 1.3.12 zostaje)" \
	|| bad "zestawienie nie podaje wieku sprawy"

grep -q 'Czas obsługi — od potwierdzenia zgłoszenia do zamknięcia' "$CSV" \
	&& ok "zestawienie nazywa podstawe czasu obslugi" \
	|| bad "zestawienie nadal nie mowi, od czego liczy"

grep -q 'zamówienie nie rozstrzyga' "$CSV" \
	&& ok "plik MOWI WPROST, ze to nasza interpretacja do potwierdzenia przez klienta" \
	|| bad "brak zdania o interpretacji — koordynator czyta CSV bez nas"

# Wiek da sie policzyc zawsze, gdy da sie policzyc czas obslugi (potwierdzenie jest
# pozniej niz zlozenie), wiec spraw z wiekiem NIE MOZE byc mniej.
Z_CZASEM=$(grep -F 'W tym z policzonym czasem obsługi' "$CSV" | head -1 | tr -d '[:alpha:]" ;ęł' | tr -dc '0-9')
Z_WIEKIEM=$(grep -F 'W tym z policzonym wiekiem sprawy' "$CSV" | head -1 | tr -dc '0-9')
[ -n "$Z_WIEKIEM" ] && [ -n "$Z_CZASEM" ] && [ "$Z_WIEKIEM" -ge "$Z_CZASEM" ] 2>/dev/null \
	&& ok "spraw z policzonym wiekiem ($Z_WIEKIEM) nie mniej niz z czasem obslugi ($Z_CZASEM)" \
	|| bad "liczniki zestawienia sie nie trzymaja (wiek=$Z_WIEKIEM, obsluga=$Z_CZASEM)"

# ── Sprzatanie: konto testowe nie zostaje w skladzie personelu ─────────────
wp user delete coordcz13 --yes >/dev/null 2>&1
rm -f "$CSV"

echo ""
echo "WYNIK CZ1-3-PODSTAWA-CZASU: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
