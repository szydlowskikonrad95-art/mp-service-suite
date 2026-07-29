#!/usr/bin/env bash
# STRAZNIK: twarde liczby w dokumentach MUSZA zgadzac sie z kodem.
#
# Powod: "dokumentacja klamie wzgledem kodu" to NAJCZESTSZA uwaga zamawiajacego
# (3x w poprzednim projekcie, wpisana do BRAMKI-ANTY-POWTORKA jako #8). Raz
# przejrzana recznie — i wrocila przy nastepnych zmianach kodu: "10 testow"
# zamiast 13, "72 godziny" zamiast 30 dni, komendy WP-CLI ktorych nie ma.
#
# Przeglad ludzki tego nie utrzyma, bo dokumenty rozjezdzaja sie przy KAZDEJ
# zmianie. Dlatego bramka jest maszyna: liczbe bierzemy Z KODU i szukamy jej
# w dokumentach. Rozjazd = czerwone CI, zanim zobaczy to klient.
#
# Uruchomienie z katalogu repo:  bash testy/dokumenty/liczby-zgodne-z-kodem.sh
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# ── liczby WZIETE Z KODU (zrodlo prawdy) ────────────────────────────────────
TABEL=$(grep -hoE "const [A-Z_]+ *= *'[a-z_]+'" mp-*/includes/Tables.php | wc -l)
STATUSOW=$(sed -n "/private const CORE = array(/,/);/p" mp-service-intake/includes/Statuses.php | grep -cE "^\s*'[^']+'\s*=>")
RODZAJOW=$(grep -oE "'(reklamacja|naprawa|zapytanie|zwrot)'" mp-service-intake/includes/FormConfig.php | sort -u | wc -l)
TESTOW_SH=$(grep -rhcE "=> *array\( *self::class" mp-*/includes/Admin/SiteHealthTests.php | awk '{s+=$1} END {print s+0}')
RETENCJA=$(grep -oE "mp_intake_pending_retention_days', *[0-9]+" mp-service-intake/includes/CaseRepo.php | grep -oE "[0-9]+$")
OKNO=$(grep -oE "CONFIRM_WINDOW_HOURS *= *[0-9]+" mp-service-intake/includes/CaseRepo.php | grep -oE "[0-9]+$")
PHP_MIN=$(grep -hoE "Requires PHP: *[0-9.]+" mp-service-intake/mp-service-intake.php | grep -oE "[0-9.]+")

# Straznik na samego straznika: licznik, ktory zwrocil pustke albo zero, oznacza
# ZEPSUTY WZORZEC, a nie "zero w kodzie" — bramka musialaby wtedy przepuscic wszystko.
for para in "tabel:$TABEL" "statusow:$STATUSOW" "rodzajow:$RODZAJOW" "testow:$TESTOW_SH" \
            "retencja:$RETENCJA" "okno:$OKNO" "php:$PHP_MIN"; do
	nazwa="${para%%:*}"; wartosc="${para##*:}"
	case "$wartosc" in
		''|0) echo "  BLAD BRAMKI: licznik '$nazwa' zwrocil [$wartosc] — wzorzec przestal pasowac do kodu."
		      echo "  Napraw wzorzec w tym pliku, zanim uwierzysz wynikowi."; exit 2 ;;
	esac
done

echo "Z KODU: tabel=$TABEL statusow=$STATUSOW rodzajow=$RODZAJOW testow-diagnostyki=$TESTOW_SH"
echo "        retencja=$RETENCJA dni, okno potwierdzenia=$OKNO h, PHP min=$PHP_MIN"
echo

# ── czy dokumenty mowia to samo ─────────────────────────────────────────────
sprawdz() { # $1=opis  $2=wzorzec-ktory-MUSI-byc  $3..=pliki
	local opis="$1" wzor="$2"; shift 2
	if grep -qiE "$wzor" "$@" 2>/dev/null; then
		ok "$opis"
	else
		bad "$opis — nie znalazlem [$wzor] w: $*"
	fi
}

# Fraza w markdownie bywa przelamana na dwie linie i pogrubiona gwiazdkami —
# `grep` czyta liniami, wiec szukalby czegos, czego nie ma, choc tekst JEST.
# Tu porownujemy tekst ZLEPIONY: bez lamania linii i bez znacznikow pogrubienia.
# ⚠️ Definicja MUSI stac przed pierwszym uzyciem: funkcja zdefiniowana nizej to
# w bashu „command not found" na stderr — kontrola cicho NIE wykonuje sie,
# a bramka dalej swieci na zielono (zlapane 28.07, dwie kontrole przepadly).
sprawdz_tekst() { # $1=opis  $2=wzorzec  $3..=pliki
	local opis="$1" wzor="$2"; shift 2
	if cat "$@" 2>/dev/null | tr '\n' ' ' | sed 's/\*\*//g; s/  */ /g' | grep -qiE "$wzor"; then
		ok "$opis"
	else
		bad "$opis — nie znalazlem [$wzor] w: $*"
	fi
}

# liczby slownie ORAZ cyfra — dokumenty klienta pisza slownie
sprawdz "README: liczba tabel = $TABEL" "$TABEL tabel" README.md dokumentacja-techniczna/DATABASE.md
sprawdz "README: liczba statusow = $STATUSOW" "$STATUSOW (konfigurowalnych )?status" README.md
sprawdz "README: liczba rodzajow spraw = $RODZAJOW" "$RODZAJOW rodzaj" README.md
case "$TESTOW_SH" in
	10) SLOWNIE="dziesięć" ;; 11) SLOWNIE="jedenaście" ;; 12) SLOWNIE="dwanaście" ;;
	13) SLOWNIE="trzynaście" ;; 14) SLOWNIE="czternaście" ;; *) SLOWNIE="__brak_mapy__" ;;
esac
sprawdz "README: liczba testow diagnostyki = $TESTOW_SH" "$SLOWNIE testów|$TESTOW_SH testów" README.md
sprawdz "ADMIN.md: liczba testow diagnostyki = $TESTOW_SH" "$TESTOW_SH testów" dla-klienta/instrukcje/ADMIN.md
sprawdz "INSTRUKCJA: retencja porzuconych = $RETENCJA dni" "$RETENCJA dniach|$RETENCJA dni" dla-klienta/INSTRUKCJA-KLIENTA.md
sprawdz "INSTRUKCJA: okno potwierdzenia = $OKNO h" "$OKNO godzin" dla-klienta/INSTRUKCJA-KLIENTA.md
sprawdz "KOORDYNATOR: retencja = $RETENCJA dni" "$RETENCJA dni" dla-klienta/instrukcje/KOORDYNATOR.md
sprawdz "STATE_MACHINE: retencja = $RETENCJA dni" "$RETENCJA dniach|$RETENCJA dni" dokumentacja-techniczna/STATE_MACHINE.md
sprawdz "PRZECZYTAJ-MNIE: minimum PHP = $PHP_MIN" "PHP $PHP_MIN" dla-klienta/PRZECZYTAJ-MNIE.txt

# ── P1.2: wymog zalacznika wg kategorii MUSI byc opisany dla klienta ────────
# Regula zyje w kodzie (konfigurowalna filtrem) — dokument ma za nia nadazac.
# Straznik na wzorzec: brak samej funkcji = zepsuty wzorzec, nie „zero wymogow".
grep -q "category_attachments_defaults" mp-service-intake/includes/FormConfig.php \
	|| { echo "  BLAD BRAMKI: nie znalazlem category_attachments_defaults — wzorzec przestal pasowac do kodu."; exit 2; }
KAT_WYMAG=$(sed -n "/function category_attachments_defaults/,/^	}/p" mp-service-intake/includes/FormConfig.php | grep -c "'required' => true")

if [ "$KAT_WYMAG" -gt 0 ]; then
	sprawdz_tekst "INSTRUKCJA: opisany wymog zalacznika wg kategorii" "tabliczk" dla-klienta/INSTRUKCJA-KLIENTA.md
	sprawdz_tekst "KLIENT.md: opisany wymog zalacznika wg kategorii" "tabliczk" dla-klienta/instrukcje/KLIENT.md
else
	ok "brak kategorii z wymaganym zalacznikiem — dokumenty nie musza o tym pisac"
fi

# ── czwarty status gwarancji (P2.2) opisany tam, gdzie ludzie go zobacza ────
sprawdz_tekst "INSTRUKCJA: czwarty status gwarancji" "wymagana weryfikacja" dla-klienta/INSTRUKCJA-KLIENTA.md
sprawdz_tekst "PRACOWNIK: czwarty status gwarancji" "wymagana weryfikacja" dla-klienta/instrukcje/PRACOWNIK.md
sprawdz_tekst "KOORDYNATOR: czwarty status gwarancji" "wymagana weryfikacja" dla-klienta/instrukcje/KOORDYNATOR.md

# Ten sam stan nie moze miec dwoch nazw na dwoch ekranach — klient czyta to
# jak dwa rozne statusy (karta sprawy mowila „do weryfikacji", rejestr
# „wymagana weryfikacja"; instrukcje opisuja jedna nazwe).
for plik in mp-service-intake/includes/Admin/CaseCard.php mp-warranty-registry/includes/Admin/ProductsTable.php; do
	grep -q "wymagana weryfikacja" "$plik" \
		&& ok "etykieta czwartego statusu spojna w: $(basename "$plik")" \
		|| bad "inna nazwa czwartego statusu w: $plik (ma byc: wymagana weryfikacja)"
done

# ── kopia przed wdrozeniem (kartka: „Kopie i odtworzenie") ──────────────────
sprawdz_tekst "INSTRUKCJA: kopia bazy PRZED instalacja" "kopi[^ ]* bazy" dla-klienta/INSTRUKCJA-KLIENTA.md
sprawdz "PRZECZYTAJ-MNIE wskazuje polityke kopii" "MIGRATION_POLICY" dla-klienta/PRZECZYTAJ-MNIE.txt
grep -q "MIGRATION_POLICY.md" build/pakuj-dla-klienta.sh \
	&& ok "skrypt pakujacy kopiuje MIGRATION_POLICY.md do paczki" \
	|| bad "dokumenty odsylaja do MIGRATION_POLICY.md, a skrypt pakujacy go nie kopiuje"

# ── ryzyko wdrozeniowe za proxy opisane PO POLSKU, nie tylko w readme.txt ───
sprawdz "INSTRUKCJA: nota o proxy/Cloudflare (filtr IP klienta)" "mp_intake_client_ip" dla-klienta/INSTRUKCJA-KLIENTA.md

# ── dokumenty NIE MOGA obiecywac tego, czego w kodzie nie ma ────────────────
brak_obietnicy() { # $1=opis  $2=wzorzec-ktorego-NIE MOZE byc  $3..=pliki
	local opis="$1" wzor="$2"; shift 2
	if grep -qiE "$wzor" "$@" 2>/dev/null; then
		bad "$opis — dokument obiecuje cos, czego kod nie ma:"
		grep -niE "$wzor" "$@" | head -3 | sed 's/^/       /'
	else
		ok "$opis"
	fi
}

grep -rq "wp mp cleanup" mp-*/includes/ 2>/dev/null \
	|| brak_obietnicy "zadna dokumentacja nie obiecuje komendy 'wp mp cleanup'" "wp mp cleanup" dokumentacja-techniczna/*.md dla-klienta/*.md README.md
grep -rq "PRODUCT_FORCE_DELETED\|force-delete" mp-warranty-registry/includes/ 2>/dev/null \
	|| brak_obietnicy "zadna dokumentacja nie obiecuje twardego kasowania produktu" "hard delete|force-delete|--confirm=<SERIAL>" dokumentacja-techniczna/*.md dla-klienta/*.md README.md

# slady wewnetrzne w materialach dla klienta (te szly juz raz do paczki)
brak_obietnicy "materialy klienta bez naszych nazw roboczych" \
	"czat B[0-9]|C-patch|C-hooki|BRAMKA-ODDANIA|flaga #[0-9]" dla-klienta/*.md dla-klienta/instrukcje/*.md dla-klienta/PRZECZYTAJ-MNIE.txt

# ── EKRANY, KTORYCH NIE MA (audyt 29.07) ────────────────────────────────────
# Instrukcja opisywala „ekran ustawien" w czterech miejscach, a istnial zero razy.
# Klient szedl wg dokumentu, nie znajdowal pola i tracil zaufanie do calej reszty.
# Kontrole ponizej sa WARUNKOWE: gdy ktos dorobi brakujacy ekran, warunek przestaje
# byc spelniony i kontrola sama znika — bez grzebania w tej bramce.

# Pula pracownikow ekran MA (1.2.0) => dokumenty MUSZA go opisywac ta sama nazwa co kod.
if grep -q "Kto dostaje zgłoszenia" mp-workflow-automator/includes/Admin/PanelScreen.php 2>/dev/null; then
	sprawdz "INSTRUKCJA: sekcja ustawiania puli nazwana tak samo jak w panelu" \
		"Kto dostaje zgłoszenia" dla-klienta/INSTRUKCJA-KLIENTA.md
	sprawdz "ADMIN: opisany pierwszy krok — wskazanie pracownikow" \
		"Kto dostaje zgłoszenia" dla-klienta/instrukcje/ADMIN.md
else
	echo "  BLAD BRAMKI: nie znalazlem sekcji puli w PanelScreen.php — wzorzec przestal pasowac do kodu."
	exit 2
fi

# Terminy SLA: brak ZAPISU konfiguracji => dokument nie moze kazac ich „ustawic w panelu".
grep -q "update_option( *self::CORE_OPTION\|update_option( *self::POLICY_OPTION" mp-workflow-automator/includes/SlaConfig.php 2>/dev/null \
	|| brak_obietnicy "zadna dokumentacja nie kaze ustawiac terminow SLA w panelu (nie ma na to ekranu)" \
		"W ustawieniach Automatora ustaw" dla-klienta/*.md dla-klienta/instrukcje/*.md

# Eksport CSV: jesli pracownik (mp_agent) NIE ma prawa eksportu, dokument nie moze
# obiecywac, ze „pracownik eksportuje tylko swoje" (zlapane 29.07 — INSTRUKCJA obiecywala,
# PRACOWNIK.md pisal prawde, kod byl po stronie PRACOWNIK.md).
grep -q "mp_agent" mp-workflow-automator/includes/CsvExport.php 2>/dev/null \
	|| brak_obietnicy "zadna dokumentacja nie obiecuje eksportu CSV pracownikowi serwisu" \
		"pracownik eksportuje" dla-klienta/*.md dla-klienta/instrukcje/*.md

# Wlasne statusy: metoda zapisu istnieje, ale nikt jej nie wola z UI => brak ekranu.
grep -rq "StatusDefs::upsert\|StatusDefs::remove" mp-workflow-automator/includes/Admin/ 2>/dev/null \
	|| brak_obietnicy "zadna dokumentacja nie obiecuje dodawania wlasnych statusow z panelu" \
		"dodać własne w ustawieniach|możliwość dodania własnych" dla-klienta/*.md dla-klienta/instrukcje/*.md

# ── Nazwy rol: dokumenty kaza klientowi wybrac role z listy w panelu ────────
# Nazwy czytamy Z KODU (Roles.php), a nie wpisujemy tutaj — inaczej bramka
# pilnowalaby wlasnej kopii prawdy. Zlapane 29.07 na zywym panelu: dwa dokumenty
# kazaly nadac range „Pracownik serwisu", a na liscie rol jest „Pracownik serwisu MP".
# INSTRUKCJA-KLIENTA przeczyla przy tym sama sobie: raz bez „MP", a kilkadziesiat
# linii dalej z dopiskiem „dokladnie tak nazywaja sie na liscie rol".
while IFS= read -r ROLA; do
	[ -n "$ROLA" ] || continue
	BAZA="${ROLA% MP}"
	[ "$BAZA" != "$ROLA" ] || continue          # rola bez sufiksu MP — nie dotyczy
	ZLE="$(grep -rn "$BAZA" dla-klienta/*.md dla-klienta/instrukcje/*.md 2>/dev/null \
		| grep -v "$ROLA" || true)"
	if [ -z "$ZLE" ]; then
		ok "nazwa roli w dokumentach zgodna z panelem: $ROLA"
	else
		bad "dokument podaje nazwe roli inaczej niz panel ($ROLA):"
		echo "$ZLE" | head -3 | sed 's/^/         /'
	fi
done < <(sed -n "s/^[[:space:]]*'mp_[a-z_]*'[[:space:]]*=>[[:space:]]*'\([^']*\)'.*/\1/p" lib/mp-common/src/Roles.php)

echo
echo "WYNIK: $PASS ok, $FAIL fail"

# Straznik na komplet kontroli: kontrola, ktora nie wystartowala (literowka
# w nazwie funkcji, przeniesiona definicja), nie zglasza sie jako FAIL — po
# prostu jej nie ma, a bramka swieci zielono. Liczba kontroli musi sie zgadzac.
MIN_KONTROLI=33
if [ "$(( PASS + FAIL ))" -lt "$MIN_KONTROLI" ]; then
	echo "  BLAD BRAMKI: wykonalo sie $(( PASS + FAIL )) kontroli, oczekiwane min. $MIN_KONTROLI."
	echo "  Ktoras cicho NIE wystartowala — sprawdz stderr i kolejnosc definicji funkcji."
	exit 2
fi

[ "$FAIL" -eq 0 ]
