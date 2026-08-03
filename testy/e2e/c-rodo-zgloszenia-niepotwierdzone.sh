#!/usr/bin/env bash
# ZYWY DOWOD (naprawa 2.58): zadanie RODO SIEGA zgloszen niepotwierdzonych.
#
# Zgloszenie, ktorego nikt nie potwierdzil, nie ma rekordu klienta — a leza w nim
# adres, telefon, opis usterki i ZALACZNIKI osoby, ktora nigdy klientem nie
# zostala. Spis erasera chodzil po klientach, wiec takiej sprawy nie widzial:
# ⛔ narzedzie meldowalo „usunieto", a dane zostawaly (do 30 dni, bez zadnej
# drogi usuniecia), i to samo zapewnienie dostawal KLIENT w panelu.
#
# Pilnujemy tu czterech rzeczy:
#   1. przed zadaniem dane SA (inaczej „zniknely" nic nie znaczy),
#   2. zadanie usuniecia je kasuje razem z odlozonymi danymi kontaktowymi,
#   3. zadanie dostepu (art. 15) je ODDAJE,
#   4. cudze zgloszenie zostaje nietkniete (kasowanie nie jest za szerokie).
# CLI (bez HTTP). Chodzi na poligonie i w CI.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }
cid() { echo "$1" | grep '^case_id=' | cut -d= -f2; }

MOJ='niepotwierdzony@przyklad.pl'
CUDZY='obcy@przyklad.pl'

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_srv_counters; DELETE FROM wp_mp_rate_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1

echo "== 1. ZGLOSZENIA NIEPOTWIERDZONE ISTNIEJA =="
O1=$(wp mp case-create --kind=reklamacja --email="$MOJ" --name='Jan Niepotwierdzony' --serial='SN-NP-1' --document='FV/NP1' --date='2026-03-15' --desc='usterka opisana w zgloszeniu' 2>/dev/null)
C1=$(cid "$O1")
O2=$(wp mp case-create --kind=naprawa --email="$CUDZY" --name='Ktos Inny' --serial='SN-NP-2' --desc='cudza sprawa' 2>/dev/null)
C2=$(cid "$O2")

[ -n "$C1" ] && [ -n "$C2" ] && ok "dwa zgloszenia niepotwierdzone utworzone ($C1, $C2)" || bad "nie udalo sie utworzyc zgloszen"

# Adres MUSI byc osiagalny dla zadania — bez tego eraser nie ma jak trafic.
PE=$(q "SELECT pending_email FROM wp_mp_service_cases WHERE id=$C1")
[ "$PE" = "$MOJ" ] && ok "adres zapisany przy sprawie (osiagalny dla zadania RODO)" || bad "pending_email=$PE"

OPCJA=$(q "SELECT COUNT(*) FROM wp_options WHERE option_name='mp_pending_contact_$C1'")
[ "$OPCJA" = "1" ] && ok "odlozone dane kontaktowe istnieja (jest co usuwac)" || bad "brak odlozonych danych kontaktowych"

echo "== 2. ZADANIE DOSTEPU (art. 15) ODDAJE TE DANE =="
EXP=$(wp eval "\$r = MP\\Intake\\Privacy::export('$MOJ'); \$g = array(); foreach (\$r['data'] as \$i) { \$g[] = \$i['group_id']; } echo implode(',', \$g);" 2>/dev/null)
case "$EXP" in *mp_pending_cases*) ok "eksport zawiera zgloszenie niepotwierdzone" ;; *) bad "eksport BEZ zgloszenia niepotwierdzonego (grupy: $EXP)" ;; esac

TRESC=$(wp eval "\$r = MP\\Intake\\Privacy::export('$MOJ'); echo wp_json_encode(\$r['data']);" 2>/dev/null)
case "$TRESC" in *"usterka opisana w zgloszeniu"*) ok "eksport oddaje TRESC z formularza" ;; *) bad "eksport bez tresci formularza" ;; esac
case "$TRESC" in *"Jan Niepotwierdzony"*) ok "eksport oddaje imie z odlozonych danych" ;; *) bad "eksport bez imienia" ;; esac

echo "== 3. ZADANIE USUNIECIA (art. 17) KASUJE JE NAPRAWDE =="
WYNIK=$(wp eval "\$r = MP\\Intake\\Privacy::erase('$MOJ'); echo \$r['items_removed'] ? 'removed' : 'nic';" 2>/dev/null)
[ "$WYNIK" = "removed" ] && ok "zadanie melduje usuniecie (i ma prawo — patrz nizej)" || bad "zadanie nie zglosilo usuniecia ($WYNIK)"

ZOSTALO=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id=$C1")
[ "$ZOSTALO" = "0" ] && ok "zgloszenie niepotwierdzone USUNIETE z bazy" || bad "zgloszenie nadal w bazie"

OPCJA_PO=$(q "SELECT COUNT(*) FROM wp_options WHERE option_name='mp_pending_contact_$C1'")
[ "$OPCJA_PO" = "0" ] && ok "odlozone dane kontaktowe usuniete" || bad "dane kontaktowe zostaly w opcjach"

echo "== 4. PROBA KONTROLNA: CUDZE ZGLOSZENIE NIETKNIETE =="
CUDZE_PO=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id=$C2")
[ "$CUDZE_PO" = "1" ] && ok "zgloszenie innej osoby zostalo nietkniete" || bad "skasowano cudze zgloszenie (kasowanie za szerokie!)"

CUDZA_OPCJA=$(q "SELECT COUNT(*) FROM wp_options WHERE option_name='mp_pending_contact_$C2'")
[ "$CUDZA_OPCJA" = "1" ] && ok "cudze dane kontaktowe zostaly nietkniete" || bad "skasowano cudze dane kontaktowe"

echo "== 5. PO WERYFIKACJI ADRES NIE ZOSTAJE W DRUGIEJ KOPII =="
O3=$(wp mp case-create --kind=naprawa --email='po.weryfikacji@przyklad.pl' --name='Po Weryfikacji' --serial='SN-NP-3' --desc='zwykla sciezka' 2>/dev/null)
C3=$(cid "$O3")
T3=$(echo "$O3" | grep '^token=' | cut -d= -f2)
wp mp case-verify "$T3" >/dev/null 2>&1
PE3=$(q "SELECT pending_email FROM wp_mp_service_cases WHERE id=$C3")
[ -z "$PE3" ] && ok "po weryfikacji adres znika ze sprawy (tozsamosc trzyma rekord klienta)" || bad "adres zostal jako druga kopia ($PE3)"

wp db query "DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_consents; DELETE FROM wp_mp_rate_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
