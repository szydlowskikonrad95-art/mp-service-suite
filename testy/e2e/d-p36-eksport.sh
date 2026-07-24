#!/usr/bin/env bash
# ZYWY DOWOD P3.6 (eksport CSV spraw + zestawienie, handler admin-post w D):
# (a) liczba wierszy = liczba spraw, (b) kolumny/wartosci, (c) zestawienie liczy
# dobrze (per status, czas obslugi, powody odrzucen), (d) CSV-formula-injection
# =SUM() wychodzi z apostrofem, (e) BOM UTF-8, (f) audyt EXPORT_GENERATED,
# (g) BRAMKA: bez uprawnien (agent/subscriber/anon) i zly nonce => brak eksportu.
# Handler testowany IN-PROCESS (wp eval): nonce generowany w tym samym procesie =
# wazny bez cookie/sieci; te same sciezki capability/nonce co przez HTTP.
# Kanoniczny HTTP-403 dla anon/subscriber/mp_client: c-dod-security-matrix.sh.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

CSV=/tmp/mp-p36-export.csv
ADMIN=1

# ── 0. Czysty stan + ZERO regul (auto-przydzial nie ma tu mieszac) ──────────
wp db query "DELETE FROM wp_mp_workflow_rules; DELETE FROM wp_mp_workflow_events; DELETE FROM wp_mp_service_cases; DELETE FROM wp_mp_case_events; DELETE FROM wp_mp_customers; DELETE FROM wp_mp_srv_counters;" >/dev/null 2>&1
wp eval 'foreach ((array) $GLOBALS["wpdb"]->get_col("SELECT option_name FROM {$GLOBALS[\"wpdb\"]->options} WHERE option_name LIKE \"mp_pending_contact_%\"") as $o) delete_option($o);' >/dev/null 2>&1

# Konta testowe (idempotentnie).
COORD=$(wp user get coord36 --field=ID 2>/dev/null)
[ -z "$COORD" ] && COORD=$(wp user create coord36 coord36@example.com --role=mp_coordinator --user_pass=x --porcelain 2>/dev/null)
AGENT=$(wp user get agent36 --field=ID 2>/dev/null)
[ -z "$AGENT" ] && AGENT=$(wp user create agent36 agent36@example.com --role=mp_agent --user_pass=x --porcelain 2>/dev/null)
SUB=$(wp user get sub36 --field=ID 2>/dev/null)
[ -z "$SUB" ] && SUB=$(wp user create sub36 sub36@example.com --role=subscriber --user_pass=x --porcelain 2>/dev/null)

mk() { # $1=kind $2=email $3=serial
	local out cid tok
	out=$(wp mp case-create --kind="$1" --email="$2" --name='Jan Kowalski' --serial="$3" --document='FV/2026/9' --date='2026-05-01' --desc='opis' --return-reason='zmiana' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\\Intake\\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}
chs() { wp eval "apply_filters('mp_case_change_status', null, $1, '$2', '$3', $ADMIN, $4);" >/dev/null 2>&1; }

# ── 1. Seed: 4 sprawy (1 nowa, 1 zamknieta, 2 odrzucone — druga z kodem-injekcja) ──
A=$(mk reklamacja a@example.com SEK-A)                                   # 'nowe'
B=$(mk zwrot      b@example.com SEK-B); chs "$B" "w analizie" "nowe" "null"; chs "$B" "zamknięte" "w analizie" "null"
C=$(mk reklamacja c@example.com SEK-C); chs "$C" "w analizie" "nowe" "null"; chs "$C" "odrzucone" "w analizie" "'duplikat'"
D=$(mk naprawa    d@example.com SEK-D); chs "$D" "w analizie" "nowe" "null"; chs "$D" "odrzucone" "w analizie" "'inny'"
# Wstrzykniecie CSV-formula w kod odrzucenia sprawy D (realny wektor: pole tekstowe personelu).
wp db query "UPDATE wp_mp_service_cases SET rejection_reason_code='=SUM(1+1)' WHERE id=$D" >/dev/null 2>&1

VER=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE identity_status='verified'")
[ "$VER" = "4" ] && ok "seed: 4 zweryfikowane sprawy" || bad "seed zly (verified=$VER)"

# ── 2. Eksport jako KOORDYNATOR (valid nonce in-process) ────────────────────
wp eval --user="$COORD" "\$_GET['_wpnonce']=wp_create_nonce('mp_automator_export_csv'); \$_REQUEST['_wpnonce']=\$_GET['_wpnonce']; MP\\Automator\\CsvExport::handle();" >"$CSV" 2>/dev/null

# (e) BOM UTF-8 na poczatku
[ "$(head -c3 "$CSV" | od -An -tx1 | tr -d ' ')" = "efbbbf" ] && ok "BOM UTF-8 na poczatku pliku" || bad "brak BOM UTF-8"

# (b) naglowek kolumn
head -1 "$CSV" | grep -q "Nr sprawy" && head -1 "$CSV" | grep -q "Powód odrzucenia (kod)" && ok "naglowek kolumn obecny" || bad "zly naglowek"

# (a) liczba wierszy danych = liczba spraw (wiersze zaczynajace sie od SRV/)
DR=$(grep -c '^SRV/' "$CSV")
[ "$DR" = "4" ] && ok "liczba wierszy danych = 4 (= liczba spraw)" || bad "wierszy danych=$DR (!=4)"

# (b) wartosci: sprawa odrzucona C ma status 'odrzucone' + kod 'duplikat'
grep -E '^SRV/[0-9]{4}/[0-9]{5,};odrzucone;' "$CSV" | grep -q 'duplikat' && ok "wiersz odrzucony: status+kod 'duplikat' obecne" || bad "brak poprawnego wiersza odrzuconego"

# (d) ANTI-INJECTION: kod '=SUM(1+1)' wychodzi z apostrofem; ZERO golego =SUM na starcie komorki
grep -qF "'=SUM(1+1)" "$CSV" && ok "anti-injection: '=SUM(1+1) poprzedzone apostrofem" || bad "brak apostrofu przed =SUM"
grep -Eq '(^|;)=SUM' "$CSV" && bad "GOLE =SUM na starcie komorki (injection!)" || ok "zadna komorka nie zaczyna sie golym =SUM"

# (c) ZESTAWIENIE: laczna liczba spraw
grep -q '"Łączna liczba spraw";4' "$CSV" && ok "zestawienie: laczna liczba spraw = 4" || bad "zla laczna liczba spraw"
# per status: nowe;1, zamkniete;1, odrzucone;2
grep -q '^nowe;1$' "$CSV" && grep -q '^zamknięte;1$' "$CSV" && grep -q '^odrzucone;2$' "$CSV" && ok "zestawienie: liczba per status (nowe1/zamkniete1/odrzucone2)" || bad "zle liczby per status"
# sprawy zamkniete (terminal): odrzucone2 + zamkniete1 = 3
grep -q '"Liczba spraw zamkniętych";3' "$CSV" && ok "zestawienie: 3 sprawy zamkniete (terminal)" || bad "zla liczba zamknietych"
# rozklad powodow: 2 powody (duplikat + =SUM...)
POW=$(awk '/Rozkład powodów/{f=1;next} f&&/;[0-9]+$/{c++} END{print c+0}' "$CSV")
[ "$POW" = "2" ] && ok "zestawienie: rozklad powodow odrzucen = 2 pozycje" || bad "zly rozklad powodow ($POW)"

# (f) AUDYT: EXPORT_GENERATED z rows=4
AUD=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='EXPORT_GENERATED'")
AR=$(wp db query "SELECT payload FROM wp_mp_workflow_events WHERE event_type='EXPORT_GENERATED' ORDER BY id DESC LIMIT 1" --skip-column-names 2>/dev/null)
[ "$AUD" = "1" ] && echo "$AR" | grep -q '"rows":4' && ok "audyt EXPORT_GENERATED zapisany (rows=4, append-only)" || bad "audyt zly (count=$AUD, payload=$AR)"

# ── 3. Filtr: tylko odrzucone => 2 wiersze danych ───────────────────────────
wp eval --user="$COORD" "\$_GET['_wpnonce']=wp_create_nonce('mp_automator_export_csv'); \$_REQUEST['_wpnonce']=\$_GET['_wpnonce']; \$_GET['status']='odrzucone'; MP\\Automator\\CsvExport::handle();" >"$CSV.f" 2>/dev/null
DF=$(grep -c '^SRV/' "$CSV.f")
[ "$DF" = "2" ] && ok "filtr status=odrzucone: 2 wiersze danych" || bad "filtr zly ($DF)"

# ── 4. BRAMKA: role bez uprawnien + zly nonce => BRAK eksportu ──────────────
AUD_BEFORE=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='EXPORT_GENERATED'")
gate() { # $1=opis $2=user-flag(pusty=anon) $3=nonce
	local out
	if [ -n "$2" ]; then
		out=$(wp eval --user="$2" "\$_GET['_wpnonce']='$3'; \$_REQUEST['_wpnonce']='$3'; MP\\Automator\\CsvExport::handle();" 2>/dev/null)
	else
		out=$(wp eval "\$_GET['_wpnonce']='$3'; \$_REQUEST['_wpnonce']='$3'; MP\\Automator\\CsvExport::handle();" 2>/dev/null)
	fi
	echo "$out" | grep -q "Nr sprawy" && bad "$1: WYCIEKL CSV!" || ok "$1: brak eksportu (bramka trzyma)"
}
NV=$(wp eval --user="$COORD" "echo wp_create_nonce('mp_automator_export_csv');" 2>/dev/null)
gate "subscriber"            "$SUB"   "$NV"
gate "mp_agent"              "$AGENT" "$NV"
gate "anon"                  ""       "$NV"
gate "koordynator zly nonce" "$COORD" "bogus-nonce"

# audyt NIE przyrosl przez zablokowane proby
AUD_AFTER=$(q "SELECT COUNT(*) FROM wp_mp_workflow_events WHERE event_type='EXPORT_GENERATED'")
[ "$AUD_AFTER" = "$AUD_BEFORE" ] && ok "zablokowane proby NIE zapisaly audytu" || bad "audyt przyrosl mimo blokady ($AUD_BEFORE->$AUD_AFTER)"

rm -f "$CSV" "$CSV.f"
# Sprzatanie userow — inaczej coord36 (mp_coordinator) zostaje i truje testy
# zakladajace BRAK koordynatora, jesli zmieni sie kolejnosc uruchamiania (np. d-p34a).
for u in "$COORD" "$AGENT" "$SUB"; do [ -n "$u" ] && wp user delete "$u" --yes >/dev/null 2>&1; done
echo ""
echo "WYNIK P3.6-eksport: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
