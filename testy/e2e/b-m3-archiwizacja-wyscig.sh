#!/usr/bin/env bash
# ZYWY DOWOD M3 (recenzja zewnetrzna 1.3.12 — archiwizacja produktu z aktywna sprawa):
# `Archive::set_archived()` LICZYLO aktywne sprawy jednym zapytaniem, a flage archiwum
# zapisywalo drugim — bez wspolnego zamka. Sprawa zalozona w oknie miedzy nimi nie mogla
# juz zatrzymac archiwizacji: produkt szedl do archiwum MIMO aktywnej sprawy, wbrew
# instrukcji („najpierw ja zamknij") i wbrew samej bramce.
# Po naprawie: oba kroki w JEDNEJ transakcji, a liczenie POD ZAMKIEM (trzeci argument
# haka `mp_product_active_cases_count` => FOR UPDATE po stronie C, wlasciciela tabeli).
#
# JAK MIERZYMY WYSCIG BEZ ZGADYWANIA. Proces A zaklada sprawe w OTWARTEJ transakcji
# i trzyma ja 3 s. Proces B probuje w tym czasie zarchiwizowac produkt:
#   · kod sprzed naprawy: liczy 0 (zapis A jeszcze niezatwierdzony) => ARCHIWIZUJE;
#   · kod po naprawie:    odczyt pod zamkiem CZEKA na COMMIT A, widzi 1 => ODMAWIA.
# Zero uspien „na chybil trafil" po stronie asercji — o wyniku decyduje baza.
#
# KALIBRACJA (kod sprzed naprawy): produkt konczy z archived=1 mimo aktywnej sprawy.
# Wymaga MP_BASE (wspolny kontrakt uruchamiania). Chodzi na poligonie i w CI.
set -u
: "${MP_BASE:?MP_BASE wymagane (kontrakt uruchamiania e2e)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp db query "$1" --skip-column-names 2>/dev/null | tr -d '[:space:]'; }

STEMPEL=$(date +%s)
SERIAL="M3-WYSCIG-$STEMPEL"
# Numer sprawy ma WLASNY limit dlugosci w bazie — dluzszy nie zapisze sie w ogole
# (wpdb odrzuca wartosc po cichu, jesli nikt nie sprawdza wyniku insertu).
KROTKI=${STEMPEL: -4}

# ── Scena: produkt bez zadnej sprawy ─────────────────────────────────────────
wp db query "INSERT INTO wp_mp_product_registry (serial_display, serial_normalized, model, category, source, archived, created_at, updated_at)
	VALUES ('$SERIAL', '$(echo "$SERIAL" | tr -d '-' | tr '[:lower:]' '[:upper:]')', 'Produkt testowy M3', 'inne', 'manual', 0, UTC_TIMESTAMP(), UTC_TIMESTAMP());" >/dev/null 2>&1
PID=$(q "SELECT id FROM wp_mp_product_registry WHERE serial_display = '$SERIAL'")
[ -n "$PID" ] && ok "produkt testowy zalozony (id=$PID)" || { bad "nie udalo sie zalozyc produktu"; echo "WYNIK M3: $PASS ok, $FAIL fail"; exit 1; }

# ── Kontrola wstepna: bez spraw archiwizacja MA przechodzic ──────────────────
# (Naprawa nie moze zablokowac normalnej pracy — to bramka, nie klodka.)
WYNIK0=$(wp --user=1 eval "var_export( MP\\Registry\\Archive::archive( $PID ) );" 2>/dev/null | tr -d '[:space:]')
ARCH0=$(q "SELECT archived FROM wp_mp_product_registry WHERE id = $PID")
{ [ "$WYNIK0" = "true" ] && [ "$ARCH0" = "1" ]; } && ok "produkt BEZ spraw archiwizuje sie normalnie" || bad "archiwizacja czystego produktu odmowiona ($WYNIK0/archived=$ARCH0)"
wp --user=1 eval "MP\\Registry\\Archive::restore( $PID );" >/dev/null 2>&1

# ── Wyscig: sprawa powstaje W TRAKCIE archiwizacji ───────────────────────────
# Proces A: transakcja trzymana 3 s (sprawa aktywna = status NULL, poza terminalnymi).
wp eval "
	global \$wpdb;
	\$wpdb->query( 'START TRANSACTION' );
	\$wpdb->insert( 'wp_mp_service_cases', array(
		'case_number'         => 'SRV/2026/M$KROTKI',
		'product_registry_id' => $PID,
		'kind'                => 'reklamacja',
		'status'              => null,
		'identity_status'     => 'verified',
		'created_at'          => gmdate( 'Y-m-d H:i:s' ),
		'updated_at'          => gmdate( 'Y-m-d H:i:s' ),
	) );
	sleep( 3 );
	\$wpdb->query( 'COMMIT' );
" >/dev/null 2>&1 &
A_PID=$!

sleep 1  # A trzyma juz otwarta transakcje z niezatwierdzona sprawa.

WYNIK=$(wp --user=1 eval "\$r = MP\\Registry\\Archive::archive( $PID ); echo is_array( \$r ) ? 'ODMOWA: ' . \$r['error'] : 'ZARCHIWIZOWANO';" 2>/dev/null)
wait "$A_PID" 2>/dev/null

ARCH=$(q "SELECT archived FROM wp_mp_product_registry WHERE id = $PID")
AKTYWNE=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE product_registry_id = $PID AND (status IS NULL OR status NOT IN ('zamkniete','odrzucone'))")

[ "$AKTYWNE" = "1" ] && ok "sprawa wyscigowa zatwierdzona (scena zbudowana poprawnie)" || bad "scena nie zbudowana — aktywnych spraw: $AKTYWNE"
[ "$ARCH" = "0" ] && ok "produkt NIE trafil do archiwum mimo wyscigu (archived=0)" || bad "produkt zarchiwizowany MIMO aktywnej sprawy (archived=$ARCH) — dziura M3"
case "$WYNIK" in
	ODMOWA*aktywn*) ok "odmowa mowi czlowiekowi o aktywnej sprawie: ${WYNIK#ODMOWA: }" ;;
	ODMOWA*)        ok "archiwizacja odmowiona: ${WYNIK#ODMOWA: }" ;;
	*)              bad "archiwizacja zameldowala sukces: $WYNIK" ;;
esac

# ── Po zamknieciu sprawy archiwizacja znow przechodzi ────────────────────────
wp db query "UPDATE wp_mp_service_cases SET status = 'zamkniete' WHERE product_registry_id = $PID;" >/dev/null 2>&1
WYNIK2=$(wp --user=1 eval "var_export( MP\\Registry\\Archive::archive( $PID ) );" 2>/dev/null | tr -d '[:space:]')
ARCH2=$(q "SELECT archived FROM wp_mp_product_registry WHERE id = $PID")
{ [ "$WYNIK2" = "true" ] && [ "$ARCH2" = "1" ]; } && ok "po zamknieciu sprawy produkt archiwizuje sie normalnie" || bad "archiwizacja po zamknieciu sprawy odmowiona ($WYNIK2/archived=$ARCH2)"

# ── Sprzatanie ───────────────────────────────────────────────────────────────
wp db query "DELETE FROM wp_mp_service_cases WHERE product_registry_id = $PID; DELETE FROM wp_mp_product_registry WHERE id = $PID;" >/dev/null 2>&1

echo
echo "WYNIK M3: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
