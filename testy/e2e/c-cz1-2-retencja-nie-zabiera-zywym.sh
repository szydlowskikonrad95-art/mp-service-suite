#!/usr/bin/env bash
# ZYWY DOWOD cz.1 pkt 2 (waga DUZA): sprzatanie retencji nie zabiera dowodow
# sprawie, ktora ZYJE — ale sprawe naprawde zamknieta dalej sprzata.
#
# BUG: `Attachments::run_retention_sweep()` kasowal zalaczniki WYLACZNIE po dacie,
# bez jakiegokolwiek warunku o stanie sprawy. Do tego `retention_until` bylo liczone
# RAZ, przy wgraniu pliku, i NIGDY nieprzeliczane — choc produkt pozwala wznowic
# sprawe ze stanu terminalnego (`CaseRepo::change_status`, REOPEN).
#
# Skutek dla czlowieka: sprawa prowadzona dluzej niz okno retencji tracila dowody
# W TRAKCIE — po cichu, bez sladu i bez kopii. Okna: reklamacja 24 mies., naprawa
# i zwrot 12, ZAPYTANIE 3 — wiec wystarczylo, ze sprawa czekala kwartal.
# Cron chodzi codziennie, wiec to nie byla mozliwosc teoretyczna.
#
# ⛔ DRUGA STRONA, bez ktorej naprawa odebralaby funkcje wszystkim: sprawa naprawde
# zamknieta i przeterminowana MA byc sprzatana, a osierocony zalacznik (bez wiersza
# sprawy) MA znikac — na tym wprost polega sciezka usuwania danych osobowych,
# ktora zostawia pliki „do posprzatania przez retencje". Kontrole 2 i 4 pilnuja,
# ze naprawa niczego z tego nie zabila.
#
# ⚠️ Zalaczniki zakladamy wierszem w bazie (tak jak `c5-rodo.sh` i `blok-s-tabletop.sh`) —
# `store_for_case` wymaga PRAWDZIWEGO uploadu HTTP (`is_uploaded_file`), a badamy
# sprzatanie, nie wgrywanie. Plik na dysku zakladamy naprawde, PRZEZ PHP, zeby dalo
# sie sprawdzic, czy zniknal RAZEM z wierszem — i zeby nalezal do wlasciciela,
# ktorym chodzi WordPress.
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

STEMPEL="$$-$(date +%s)"
PRZESZLOSC='2020-01-01 00:00:00'

# Sprawa zakladana droga produktu (polecenie + potwierdzenie), zeby miala
# kartoteke, numer i stan `verified` — bez tego zmiana statusu sie nie uda.
mkcase() {
	local out cid tok
	out=$(wp mp case-create --kind="$1" --email="ret-$2-${STEMPEL}@example.com" --name='T Ret' \
		--serial="RET-$2-${STEMPEL}" --document='FV/2026/9' --date='2026-05-01' --desc='x' 2>/dev/null)
	cid=$(echo "$out" | grep '^case_id=' | cut -d= -f2)
	tok=$(echo "$out" | grep '^token=' | cut -d= -f2)
	wp eval "MP\Intake\CaseRepo::verify('$tok');" >/dev/null 2>&1
	echo "$cid"
}

# To samo, ale BEZ potwierdzenia — zgloszenie porzucone przez klienta.
mkcase_niepotwierdzona() {
	wp mp case-create --kind="$1" --email="ret-$2-${STEMPEL}@example.com" --name='T Ret' \
		--serial="RET-$2-${STEMPEL}" --document='FV/2026/9' --date='2026-05-01' --desc='x' 2>/dev/null \
		| grep '^case_id=' | cut -d= -f2
}

# Zalacznik PRZETERMINOWANY: wiersz + prawdziwy plik na dysku.
zalacznik_przeterminowany() {
	local cid="$1" nazwa="zalacznik-${2}-${STEMPEL}.bin"
	wp eval "
		\$u   = wp_upload_dir();
		\$dir = rtrim( (string) \$u['basedir'], '/' ) . '/mp-attachments';
		wp_mkdir_p( \$dir );
		file_put_contents( \$dir . '/$nazwa', 'dowod w sprawie' );" >/dev/null 2>&1
	wp db query "INSERT INTO wp_mp_attachments (case_id, path, mime, size_bytes, original_name, retention_until, created_at)
		VALUES ($cid, '$nazwa', 'image/jpeg', 15, 'dowod.jpg', '$PRZESZLOSC', UTC_TIMESTAMP())" >/dev/null 2>&1
	echo "$nazwa"
}

zyje() { q "SELECT COUNT(*) FROM wp_mp_attachments WHERE path='$1' AND deleted_at IS NULL"; }

plik_istnieje() {
	wp eval "
		\$u = wp_upload_dir();
		echo is_file( rtrim( (string) \$u['basedir'], '/' ) . '/mp-attachments/$1' ) ? 'tak' : 'nie';" 2>/dev/null | tr -d '[:space:]'
}

status_sql() { wp db query "UPDATE wp_mp_service_cases SET status='$2' WHERE id=$1" >/dev/null 2>&1; }

# ── PRZYGOTOWANIE PIECIU SCEN ─────────────────────────────────────────────
CID_ZYWA=$(mkcase zapytanie zywa)
CID_ZAMK=$(mkcase zapytanie zamk)
CID_WZNOW=$(mkcase zapytanie wznow)
CID_SIEROTA=$(mkcase zapytanie sierota)
CID_PENDING=$(mkcase_niepotwierdzona zapytanie pending)

P_ZYWA=$(zalacznik_przeterminowany "$CID_ZYWA" zywa)
P_ZAMK=$(zalacznik_przeterminowany "$CID_ZAMK" zamk)
P_WZNOW=$(zalacznik_przeterminowany "$CID_WZNOW" wznow)
P_SIEROTA=$(zalacznik_przeterminowany "$CID_SIEROTA" sierota)
P_PENDING=$(zalacznik_przeterminowany "$CID_PENDING" pending)

status_sql "$CID_ZYWA" 'w analizie'
status_sql "$CID_ZAMK" 'zamknięte'
status_sql "$CID_WZNOW" 'zamknięte'

# Wznowienie idzie DROGA PRODUKTU (uprawnienie koordynatora), nie UPDATE-em —
# inaczej test nie dotknalby tej samej sciezki, ktora ma chronic.
WZNOWIONE=$(wp eval "
	wp_set_current_user(1);
	\$r = MP\\Intake\\CaseRepo::change_status( $CID_WZNOW, 'w analizie', 'zamknięte', 1 );
	echo empty( \$r['success'] ) ? ( 'BLAD:' . ( \$r['error_code'] ?? '?' ) ) : 'OK';" 2>/dev/null | tr -d '[:space:]')

# Sierota: kasujemy WIERSZ SPRAWY, zalacznik zostaje bez rodzica.
wp db query "DELETE FROM wp_mp_service_cases WHERE id=$CID_SIEROTA" >/dev/null 2>&1

# Termin przeterminowany USTAWIAMY PONOWNIE — zamkniecie/wznowienie moglo go
# przeliczyc, a scena wymaga, zeby data byla w przeszlosci.
wp db query "UPDATE wp_mp_attachments SET retention_until='$PRZESZLOSC'
	WHERE path IN ('$P_ZYWA','$P_ZAMK','$P_WZNOW','$P_SIEROTA','$P_PENDING')" >/dev/null 2>&1

GOTOWE=$(q "SELECT COUNT(*) FROM wp_mp_attachments WHERE path IN ('$P_ZYWA','$P_ZAMK','$P_WZNOW','$P_SIEROTA','$P_PENDING') AND deleted_at IS NULL AND retention_until < UTC_TIMESTAMP()")
{ [ "$GOTOWE" = "5" ] && [ "$WZNOWIONE" = "OK" ]; } \
	&& ok "stan wyjsciowy: 5 przeterminowanych zalacznikow, sprawa wznowiona droga produktu" \
	|| bad "stan wyjsciowy zly (przeterminowanych=$GOTOWE, wznowienie=$WZNOWIONE) — test nic nie dowiedzie"

# ── SPRZATANIE RETENCJI ──────────────────────────────────────────────────
SKASOWANE=$(wp eval "echo MP\\Intake\\Attachments::run_retention_sweep();" 2>/dev/null | tr -d '[:space:]')

# ── 1. SEDNO: sprawa ZYWA nie traci dowodow ──────────────────────────────
[ "$(zyje "$P_ZYWA")" = "1" ] \
	&& ok "SEDNO: sprawa ZYWA zachowala zalacznik mimo przekroczonej daty" \
	|| bad "sprawa w toku stracila DOWOD po przekroczeniu daty (to jest wada cz.1 pkt 2)"

[ "$(plik_istnieje "$P_ZYWA")" = "tak" ] \
	&& ok "plik zywej sprawy nadal lezy na dysku" \
	|| bad "plik zywej sprawy skasowany z dysku"

# ── 2. DRUGA STRONA: sprawa naprawde ZAMKNIETA dalej jest sprzatana ──────
# Bez tej kontroli naprawa mogla by po prostu wylaczyc retencje wszystkim.
[ "$(zyje "$P_ZAMK")" = "0" ] \
	&& ok "sprawa ZAMKNIETA i przeterminowana zostala posprzatana (retencja dalej dziala)" \
	|| bad "zamknieta sprawa NIE zostala posprzatana — naprawa odebrala funkcje retencji"

[ "$(plik_istnieje "$P_ZAMK")" = "nie" ] \
	&& ok "plik zamknietej sprawy zniknal takze z dysku" \
	|| bad "wiersz skasowany, ale plik ZOSTAL na dysku"

# ── 3. Sprawa WZNOWIONA jest traktowana jak zywa ─────────────────────────
[ "$(zyje "$P_WZNOW")" = "1" ] \
	&& ok "sprawa WZNOWIONA zachowala zalacznik (termin nie biegnie dla sprawy w toku)" \
	|| bad "wznowiona sprawa stracila dowody — wznowienie nie chroni zalacznikow"

# ── 4. SIEROTA dalej znika (na tym polega sciezka RODO) ──────────────────
# Usuwanie danych osobowych zostawia pliki „do posprzatania przez retencje".
# Gdyby naprawa zwyklym zlaczeniem odcieta ta galaz, pliki zostalyby NA ZAWSZE.
[ "$(zyje "$P_SIEROTA")" = "0" ] \
	&& ok "osierocony zalacznik (brak wiersza sprawy) dalej jest sprzatany" \
	|| bad "osierocony zalacznik przestal byc sprzatany — zlamana sciezka RODO"

# ── 4b. Zgloszenie NIGDY NIEPOTWIERDZONE tez jest sprzatane ──────────────
# Klient nie dokonczyl zgloszenia — to nie jest praca w toku. Gdyby takie pliki
# przestaly znikac, zatkalyby WLASNY limit przestrzeni zgloszen niepotwierdzonych
# (`pending_usage_bytes`) plikami po ludziach, ktorzy nigdy nie potwierdzili.
# ⚠️ Tej granicy pilnuje tez `c4-zalaczniki.sh` — kontrola stoi i tutaj, zeby
# widac ja bylo przy TEJ naprawie, a nie dopiero po czerwonym CI.
[ "$(zyje "$P_PENDING")" = "0" ] \
	&& ok "zgloszenie niepotwierdzone dalej jest sprzatane (limit pending nie zatka sie porzuconymi plikami)" \
	|| bad "porzucone zgloszenie niepotwierdzone przestalo byc sprzatane — zatka limit przestrzeni"

[ "${SKASOWANE:-0}" = "3" ] \
	&& ok "sprzatanie zglosilo dokladnie 3 skasowane (zamknieta + sierota + niepotwierdzona)" \
	|| bad "sprzatanie zglosilo [$SKASOWANE] zamiast 3"

# ── 5. Zamkniecie sprawy PRZELICZA termin retencji ───────────────────────
# Druga polowa wady: termin liczony raz przy wgraniu znaczyl „N miesiecy od
# wgrania pliku", a ma znaczyc „N miesiecy od zamkniecia sprawy".
CID_PRZELICZ=$(mkcase zapytanie przelicz)
P_PRZELICZ=$(zalacznik_przeterminowany "$CID_PRZELICZ" przelicz)
status_sql "$CID_PRZELICZ" 'w analizie'

TERMIN_PRZED=$(q "SELECT retention_until FROM wp_mp_attachments WHERE path='$P_PRZELICZ'")

ZAMKNIETE=$(wp eval "
	wp_set_current_user(1);
	\$r = MP\\Intake\\CaseRepo::change_status( $CID_PRZELICZ, 'zamknięte', 'w analizie', 1 );
	echo empty( \$r['success'] ) ? ( 'BLAD:' . ( \$r['error_code'] ?? '?' ) ) : 'OK';" 2>/dev/null | tr -d '[:space:]')

[ "$ZAMKNIETE" = "OK" ] \
	&& ok "sprawa zamknieta droga produktu (scena kontroli 5 gotowa)" \
	|| bad "nie udalo sie zamknac sprawy ($ZAMKNIETE) — kontrola 5 nic nie dowiedzie"

PRZYSZLY=$(q "SELECT COUNT(*) FROM wp_mp_attachments WHERE path='$P_PRZELICZ' AND retention_until > UTC_TIMESTAMP()")
[ "${PRZYSZLY:-0}" = "1" ] \
	&& ok "zamkniecie sprawy PRZELICZYLO termin retencji (biegnie od zamkniecia, nie od wgrania)" \
	|| bad "termin nie zostal przeliczony przy zamknieciu (byl $TERMIN_PRZED) — dowod zniknalby przy najblizszym sprzataniu"

# ── 6. Terminalny status WLASNY tez jest sprzatany ───────────────────────
# Lista statusow konczacych nie moze byc zaszyta: administrator dodaje wlasne
# i sam oznacza je jako konczace. Filtr rejestrujemy w TYM SAMYM wywolaniu,
# w ktorym chodzi sprzatanie — inaczej nie bylby aktywny.
CID_WLASNY=$(mkcase zapytanie wlasny)
P_WLASNY=$(zalacznik_przeterminowany "$CID_WLASNY" wlasny)
status_sql "$CID_WLASNY" 'rozliczone'
wp db query "UPDATE wp_mp_attachments SET retention_until='$PRZESZLOSC' WHERE path='$P_WLASNY'" >/dev/null 2>&1

wp eval "
	add_filter( 'mp_registered_statuses', function( \$s ) {
		\$s['rozliczone'] = array( 'label' => 'Rozliczone', 'terminal' => true );
		return \$s;
	} );
	MP\\Intake\\Attachments::run_retention_sweep();" >/dev/null 2>&1

[ "$(zyje "$P_WLASNY")" = "0" ] \
	&& ok "wlasny status admina oznaczony jako konczacy tez uruchamia sprzatanie" \
	|| bad "sprawa w konczacym statusie WLASNYM nie zostala posprzatana (lista terminalnych zaszyta na sztywno?)"

# ── 7. SPRZATANIE ZE SPRAWDZENIEM ────────────────────────────────────────
wp db query "DELETE FROM wp_mp_attachments WHERE path IN ('$P_ZYWA','$P_ZAMK','$P_WZNOW','$P_SIEROTA','$P_PENDING','$P_PRZELICZ','$P_WLASNY')" >/dev/null 2>&1
wp eval "
	\$u   = wp_upload_dir();
	\$dir = rtrim( (string) \$u['basedir'], '/' ) . '/mp-attachments';
	foreach ( array('$P_ZYWA','$P_ZAMK','$P_WZNOW','$P_SIEROTA','$P_PENDING','$P_PRZELICZ','$P_WLASNY') as \$p ) {
		if ( is_file( \$dir . '/' . \$p ) ) { wp_delete_file( \$dir . '/' . \$p ); }
	}" >/dev/null 2>&1
for c in "$CID_ZYWA" "$CID_ZAMK" "$CID_WZNOW" "$CID_PENDING" "$CID_PRZELICZ" "$CID_WLASNY"; do
	wp db query "DELETE FROM wp_mp_case_events WHERE case_id=$c; DELETE FROM wp_mp_case_sla WHERE case_id=$c; DELETE FROM wp_mp_service_cases WHERE id=$c;" >/dev/null 2>&1
done

ZOSTALO=$(q "SELECT COUNT(*) FROM wp_mp_attachments WHERE path IN ('$P_ZYWA','$P_ZAMK','$P_WZNOW','$P_SIEROTA','$P_PENDING','$P_PRZELICZ','$P_WLASNY')")
[ "${ZOSTALO:-1}" = "0" ] \
	&& ok "sceny testowe posprzatane" \
	|| bad "zostawiamy dane testowe ($ZOSTALO)"

echo ""
echo "WYNIK cz.1 pkt 2: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
