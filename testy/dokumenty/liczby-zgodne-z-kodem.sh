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

echo
echo "WYNIK: $PASS ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
