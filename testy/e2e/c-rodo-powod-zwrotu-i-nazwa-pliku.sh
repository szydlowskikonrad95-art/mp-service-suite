#!/usr/bin/env bash
# RODO, dwie wady z audytu — jedno zdanie dla klienta: ZADANIE USUNIECIA DANYCH
# NIE USUWALO WSZYSTKICH DANYCH.
#
#  (a) „Powod zwrotu" (`return_reason`) to SWOBODNY TEKST klienta, ale mial
#      `pii_sensitive => false`, a redakcja (`CaseRepo::redact_pii_fields`) pomija
#      pola bez tej flagi. Tresc zostawala w bazie po wykonanym zadaniu. Blizniacze
#      `issue_description` flage mialo — czyli przeoczenie, nie decyzja.
#  (b) Kasowanie zalacznika robilo `UPDATE deleted_at` i tyle. Plik znikal z dysku,
#      ale w wierszu zostawala `original_name`, czyli NAZWA NADANA PRZEZ KLIENTA —
#      a skany dowodow zakupu ludzie nazywaja wlasnym imieniem i nazwiskiem.
#      Wiersz zostaje (jest sladem operacji), ale bez tresci osobowej.
#
# ⭐ PRZYPADEK KONTROLNY JEST TU POLOWA DOWODU: druga sprawa, NIEOBJETA zadaniem,
# ma zostac NIETKNIETA. Bez tego „naprawa", ktora czysci wszystkim wszystko,
# przeszlaby ten test na zielono.
#
# KALIBRACJA: na kodzie SPRZED naprawy musza PASC dokladnie dwie kontrole sedna
# (powod zwrotu + nazwa pliku), a kontrole przypadku kontrolnego maja przejsc
# TAK SAMO przed i po.
#
# Chodzi na poligonie i w CI. Exit 0 = zero FAIL.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
q()   { wp eval "global \$wpdb; \$v = \$wpdb->get_var( \"$1\" ); echo null === \$v ? '' : \$v;" 2>/dev/null | tr -d '\n'; }
wykonaj() { wp eval "global \$wpdb; \$wpdb->query( \"$1\" );" >/dev/null 2>&1; }

STEMPEL="$$-$(date +%s)"
MAIL_A="rodo-a-${STEMPEL}@example.com"
MAIL_B="rodo-b-${STEMPEL}@example.com"
TRESC_A="POWOD-ZWROTU-A-${STEMPEL}"
TRESC_B="POWOD-ZWROTU-B-${STEMPEL}"
PLIK_A="Jan Kowalski faktura ${STEMPEL}.pdf"
PLIK_B="Anna Nowak paragon ${STEMPEL}.pdf"

# ⛔ Wolamy DOKLADNIE te dwie bramki, ktore wola mechanizm RODO: `redact_pii_for_cases`
# (Privacy.php:117) i `delete_for_cases` (Privacy.php:175). Pelnej sciezki erasera nie
# odgrywamy, bo ona najpierw sprawdza, czy klient nie ma AKTYWNEJ sprawy, i wtedy
# odracza wszystko en bloc — mierzylibysmy odroczenie, nie redakcje.

# Sprawa zakladana WPROST, z flaga `pii_sensitive` USTAWIONA NA FALSE w wierszu —
# czyli tak, jak wygladaja sprawy zlozone PRZED ta poprawka. To jest sedno drugiej
# czesci naprawy: gdyby redakcja wierzyla wylacznie fladze z wiersza, stare sprawy
# zostalyby brudne mimo poprawionej konfiguracji.
# ⚠️ `case_number` ma indeks UNIKALNY i domyslnie pusty napis, wiec dwa wiersze bez
# numeru sie nie zmieszcza — kazda sprawa testowa dostaje wlasny numer. Zlapane
# przebiegiem: druga sprawa cicho nie powstawala, a test meldowal „pomiar niewazny".
zaloz_sprawe() { # $1=mail $2=tresc powodu $3=przyrostek numeru; echo ID
	wp eval "
		global \$wpdb;
		\$dane = array(
			'return_reason' => array( 'key' => 'return_reason', 'label' => 'Powod zwrotu', 'value' => '$2', 'pii_sensitive' => false ),
			'serial'        => array( 'key' => 'serial', 'label' => 'Numer seryjny', 'value' => 'RODO-$STEMPEL', 'pii_sensitive' => false ),
		);
		\$wpdb->insert( MP\\Intake\\Tables::full( MP\\Intake\\Tables::CASES ), array(
			'kind'              => 'zwrot',
			'status'            => 'nowe',
			'identity_status'   => 'verified',
			'form_data'         => wp_json_encode( \$dane ),
			'case_number'       => 'SRV/2026/T$3',
			'pending_email'     => '$1',
			'created_at'        => gmdate( 'Y-m-d H:i:s' ),
			'status_changed_at' => gmdate( 'Y-m-d H:i:s' ),
		) );
		echo (int) \$wpdb->insert_id;
	" 2>/dev/null | tr -d '[:space:]'
}

ID_A=$(zaloz_sprawe "$MAIL_A" "$TRESC_A" "A$$")
ID_B=$(zaloz_sprawe "$MAIL_B" "$TRESC_B" "B$$")

if [ -z "$ID_A" ] || [ "$ID_A" = "0" ] || [ -z "$ID_B" ] || [ "$ID_B" = "0" ]; then
	echo "  FAIL pomiar niewazny: nie udalo sie zalozyc spraw testowych (A='$ID_A' B='$ID_B')"
	echo "WYNIK: 0 ok, 1 fail"
	exit 1
fi
ok "sprawy testowe zalozone ze STARA flaga w wierszu (A=$ID_A objeta zadaniem, B=$ID_B kontrolna)"

dodaj_zalacznik() { # $1=case_id $2=nazwa
	wp eval "
		global \$wpdb;
		\$wpdb->insert( MP\\Intake\\Tables::full( MP\\Intake\\Tables::ATTACHMENTS ), array(
			'case_id'       => $1,
			'path'          => wp_generate_uuid4(),
			'mime'          => 'application/pdf',
			'size_bytes'    => 1024,
			'original_name' => '$2',
			'created_at'    => gmdate( 'Y-m-d H:i:s' ),
		) );
		echo (int) \$wpdb->insert_id;
	" 2>/dev/null | tr -d '[:space:]'
}
ZAL_A=$(dodaj_zalacznik "$ID_A" "$PLIK_A")
ZAL_B=$(dodaj_zalacznik "$ID_B" "$PLIK_B")
[ -n "$ZAL_A" ] && [ "$ZAL_A" != "0" ] && [ -n "$ZAL_B" ] && [ "$ZAL_B" != "0" ] \
	&& ok "zalaczniki testowe zalozone (A=$ZAL_A, B=$ZAL_B)" \
	|| bad "nie udalo sie zalozyc zalacznikow — sedno (b) nie zostanie zmierzone"

# Stan WYJSCIOWY: obie tresci naprawde sa w bazie. Bez tego „nie ma jej po zadaniu"
# i „nigdy jej nie bylo" wygladaja tak samo.
ILE_A=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id = $ID_A AND form_data LIKE '%$TRESC_A%'")
[ "${ILE_A:-0}" = "1" ] && ok "stan wyjsciowy: powod zwrotu A JEST w bazie" \
	|| bad "stan wyjsciowy: powodu zwrotu A nie ma w bazie — test nic nie dowiedzie"

echo
echo "== ZADANIE USUNIECIA DANYCH — obie bramki dla sprawy A =="
wp eval "MP\\Intake\\CaseRepo::redact_pii_for_cases( array( $ID_A ) );" >/dev/null 2>&1
wp eval "MP\\Intake\\Attachments::delete_for_cases( array( $ID_A ) );" >/dev/null 2>&1

echo
echo "== 1. SEDNO (a): powod zwrotu znika z bazy =="
PO_A=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id = $ID_A AND form_data LIKE '%$TRESC_A%'")
[ "${PO_A:-1}" = "0" ] \
	&& ok "po zadaniu: tresci Powodu zwrotu NIE MA juz w sprawie A" \
	|| bad "po zadaniu tresc Powodu zwrotu DALEJ jest w bazie (trafien: $PO_A) — usuniecie danych nie usuwa wszystkich danych"

echo
echo "== 2. SEDNO (b): nazwa pliku nadana przez klienta znika =="
PO_ZAL=$(q "SELECT COUNT(*) FROM wp_mp_attachments WHERE id = $ZAL_A AND original_name LIKE '%Jan Kowalski%'")
[ "${PO_ZAL:-1}" = "0" ] \
	&& ok "po zadaniu: nazwy pliku nadanej przez klienta NIE MA w wierszu zalacznika" \
	|| bad "po zadaniu w wierszu zalacznika DALEJ stoi nazwa od klienta (trafien: $PO_ZAL)"

ZOSTAL_WIERSZ=$(q "SELECT COUNT(*) FROM wp_mp_attachments WHERE id = $ZAL_A")
[ "${ZOSTAL_WIERSZ:-0}" = "1" ] \
	&& ok "wiersz zalacznika ZOSTAJE (slad operacji zachowany), ale bez tresci osobowej" \
	|| bad "wiersz zalacznika zniknal — slad operacji utracony (trafien: $ZOSTAL_WIERSZ)"

echo
echo "== 3. PRZYPADEK KONTROLNY: sprawa B, NIEOBJETA zadaniem, nietknieta =="
B_POWOD=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id = $ID_B AND form_data LIKE '%$TRESC_B%'")
[ "${B_POWOD:-0}" = "1" ] \
	&& ok "powod zwrotu sprawy B NIETKNIETY" \
	|| bad "powod zwrotu sprawy B zniknal — zadanie jednego klienta wyczyscilo dane drugiego"

B_PLIK=$(q "SELECT COUNT(*) FROM wp_mp_attachments WHERE id = $ZAL_B AND original_name LIKE '%Anna Nowak%'")
[ "${B_PLIK:-0}" = "1" ] \
	&& ok "nazwa pliku sprawy B NIETKNIETA" \
	|| bad "nazwa pliku sprawy B zniknela — redakcja objela cudze dane"

echo
echo "== 4. Kontrola, ze redakcja nie wyczyscila CALEJ sprawy A =="
A_ISTNIEJE=$(q "SELECT COUNT(*) FROM wp_mp_service_cases WHERE id = $ID_A")
[ "${A_ISTNIEJE:-0}" = "1" ] \
	&& ok "sprawa A dalej istnieje (anonimizacja, nie kasowanie sprawy)" \
	|| bad "sprawa A zniknela z bazy — to nie jest anonimizacja"

# Sprzatanie po sobie.
wykonaj "DELETE FROM wp_mp_attachments WHERE id IN ($ZAL_A, $ZAL_B)"
wykonaj "DELETE FROM wp_mp_service_cases WHERE id IN ($ID_A, $ID_B)"

echo
echo "WYNIK: $PASS ok, $FAIL fail"

# ⛔ STRAZNIK KOMPLETU: kontrola, ktora cicho NIE wystartuje (literowka, rozbity
# cudzyslow w komunikacie), nie zglasza sie jako FAIL — po prostu jej nie ma,
# a bramka swieci zielono. Zlapane wlasna kalibracja: polskie cudzyslowy w tresci
# komunikatu rozbijaly argument i sedno (a) nie wykonywalo sie ani razu.
RAZEM=$(( PASS + FAIL ))
if [ "$RAZEM" -lt 9 ]; then
	echo "  BLAD PRZYRZADU: wykonalo sie $RAZEM kontroli, oczekiwane 9 — ktoras nie wystartowala."
	exit 2
fi

[ "$FAIL" -eq 0 ]
