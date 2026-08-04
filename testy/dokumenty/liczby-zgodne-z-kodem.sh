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
# ⛔ CO TA BRAMKA POKRYWA, A CZEGO NIE — czytaj, ZANIM uznasz zielony wynik za dowod.
# Nazwa („liczby w dokumentach zgodne z kodem") i zielony wynik sugeruja pokrycie
# PELNE. Nie jest pelne i nigdy nie bylo. Kontrola wybiorcza, ktora wyglada na
# calosciowa, jest grozniejsza niz brak kontroli, bo wytwarza zaufanie (poz. 2.36).
#
# POKRYTE (liczba brana Z KODU i szukana w dokumentach):
#   · liczba tabel, statusow rdzenia, rodzajow spraw, testow diagnostyki,
#   · retencja zgloszen niepotwierdzonych (dni), okno potwierdzenia (h),
#   · WAZNOSC LINKU potwierdzajacego (TOKEN_TTL_HOURS) — w INSTRUKCJA-KLIENTA.md
#     i KOORDYNATOR.md, ze sprawdzeniem, ze zdanie o niej w ogole istnieje,
#   · minimalna wersja PHP, progi ochrony formularza (e-mail / serial / IP),
#   · nazwy rol i statusow w dokumentach ORAZ w napisach na ekranach,
#   · brak obietnic bez pokrycia (komendy i funkcje, ktorych kod nie ma),
#   · liczba kontroli deklarowana w JAKOSC-I-AUDYTY.md (pilnuje sie sama).
#
# ⛔ NIEPOKRYTE — tu bramka NIE POWIE ANI SLOWA:
#   · godziny terminow SLA per status (konfigurowalne od 1.3.12 — dokumenty podaja
#     je jako PRZYKLAD „np. 24 godziny", wiec twardego zrodla prawdy nie ma),
#   · tresci szablonow wiadomosci i ich liczba,
#   · zrzuty ekranu i to, co na nich widac (maszyna nie oceni obrazka),
#   · zgodnosc instrukcji z UKLADEM ekranu (nazwy przyciskow czesciowo, reszta nie),
#   · liczby w dokumentach POZA lista plikow wymieniona w tym skrypcie.
#
# Uruchomienie z katalogu repo:  bash testy/dokumenty/liczby-zgodne-z-kodem.sh
set -u

PASS=0; FAIL=0

# Straznik na komplet kontroli: kontrola, ktora nie wystartowala (literowka
# w nazwie funkcji, przeniesiona definicja), nie zglasza sie jako FAIL — po
# prostu jej nie ma, a bramka swieci zielono. Liczba kontroli musi sie zgadzac.
#
# ⛔ TA LICZBA JEST ZMIERZONA, NIE OSZACOWANA. Stan na 4.08.2026, na scalonym `main`
# (po #254): pelny przebieg wykonal 56 kontroli — policzone dwa razy, niezaleznie:
# licznikiem samego skryptu (PASS+FAIL) i zliczeniem wierszy wydruku
# (`bash testy/dokumenty/liczby-zgodne-z-kodem.sh | grep -cE '^  (OK|FAIL)'`).
# Wczesniej stalo 44 przy 55 wykonywanych — czyli byl luz na JEDENASCIE kontroli,
# ktore mogly cicho zniknac, a straznik by tego nie zobaczyl. Prog ma stac
# DOKLADNIE na liczbie wykonywanych, bo inaczej pilnuje sam siebie, nie kontroli.
#
# ⚠️ CZESC KONTROLI JEST WARUNKOWA — odpalaja sie tylko, gdy w dokumencie stoi
# konkretna fraza albo gdy w kodzie czegos NIE MA. Przeformulowanie zdania
# w dokumencie albo dolozenie czegos do kodu WYLACZY taka kontrole i ten straznik
# zaswieci na czerwono. To jest zamierzone: znikniecie kontroli ma byc widoczne,
# a nie ciche. Gdy zniknieta kontrola jest uzasadniona — zmien te liczbe i dopisz
# w komentarzu, ktora to i dlaczego.
#
# PO DOLOZENIU KONTROLI: uruchom bramke, przepisz nowa liczbe TUTAJ. Nie zgaduj.
MIN_KONTROLI=56

ok()  { PASS=$((PASS+1)); echo "  OK   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# ── liczby WZIETE Z KODU (zrodlo prawdy) ────────────────────────────────────
TABEL=$(grep -hoE "const [A-Z_]+ *= *'[a-z_]+'" mp-*/includes/Tables.php | wc -l)
STATUSOW=$(sed -n "/private const CORE = array(/,/);/p" mp-service-intake/includes/Statuses.php | grep -cE "^\s*'[^']+'\s*=>")
RODZAJOW=$(grep -oE "'(reklamacja|naprawa|zapytanie|zwrot)'" mp-service-intake/includes/FormConfig.php | sort -u | wc -l)
TESTOW_SH=$(grep -rhcE "=> *array\( *self::class" mp-*/includes/Admin/SiteHealthTests.php | awk '{s+=$1} END {print s+0}')
RETENCJA=$(grep -oE "mp_intake_pending_retention_days', *[0-9]+" mp-service-intake/includes/CaseRepo.php | grep -oE "[0-9]+$")
OKNO=$(grep -oE "CONFIRM_WINDOW_HOURS *= *[0-9]+" mp-service-intake/includes/CaseRepo.php | grep -oE "[0-9]+$")
# 2.34: waznosc LINKU to INNA stala niz okno potwierdzenia — pomylenie ich bylo
# cala wada tej pozycji. Odczyt stoi TU, razem z pozostalymi, a nie przy samej
# kontroli: zmienna uzyta przed przypisaniem byla by pusta, a kontrola swiecilaby
# na zielono, nic nie porownujac.
TTL=$(grep -oE "TOKEN_TTL_HOURS *= *[0-9]+" mp-service-intake/includes/CaseRepo.php | grep -oE "[0-9]+$")

[ -n "$TTL" ] || { echo "  BLAD BRAMKI: nie odczytalem TOKEN_TTL_HOURS z kodu — wzorzec przestal pasowac."; exit 2; }
PHP_MIN=$(grep -hoE "Requires PHP: *[0-9.]+" mp-service-intake/mp-service-intake.php | grep -oE "[0-9.]+")
# Progi ochrony formularza — dokumenty podaja je klientowi liczbowo, wiec musza zgadzac sie
# z kodem. Zmiana progu bez poprawki instrukcji = obsluga mowi klientowi nieprawde.
# ⚠️ Czytamy WYLACZNIE z funkcji `limits()`. Te same klucze (`ip_max`, `email_max`) wystepuja
# drugi raz w progach LOGOWANIA (`login_rate_limits`) — wzorzec po calym pliku zwracal DWIE
# wartosci naraz („3” i „5”), co daje zepsuty wzorzec i bramke swiecaca na zielono.
PROGI_FORMULARZA=$(sed -n "/private static function limits/,/^	}/p" mp-service-intake/includes/RateLimit.php)
LIMIT_MAIL=$(printf '%s' "$PROGI_FORMULARZA" | grep -oE "'email_max' *=> *[0-9]+" | grep -oE "[0-9]+$")
LIMIT_SERIAL=$(printf '%s' "$PROGI_FORMULARZA" | grep -oE "'serial_max' *=> *[0-9]+" | grep -oE "[0-9]+$")
LIMIT_IP=$(printf '%s' "$PROGI_FORMULARZA" | grep -oE "'ip_max' *=> *[0-9]+" | grep -oE "[0-9]+$")

# Straznik: licznik, ktory zlapal WIECEJ NIZ JEDNA wartosc, jest zepsuty tak samo jak pusty —
# w porownaniu trafia wtedy wieloliniowy smiec, a nie liczba.
for para in "limit-mail:$LIMIT_MAIL" "limit-serial:$LIMIT_SERIAL" "limit-ip:$LIMIT_IP"; do
	if [ "$(printf '%s' "${para##*:}" | grep -c .)" -ne 1 ]; then
		echo "  BLAD BRAMKI: licznik '${para%%:*}' zwrocil [${para##*:}] — spodziewana DOKLADNIE jedna liczba."
		echo "  Wzorzec lapie wiecej niz jedno miejsce w kodzie. Napraw go, zanim uwierzysz wynikowi."
		exit 2
	fi
done

# Straznik na samego straznika: licznik, ktory zwrocil pustke albo zero, oznacza
# ZEPSUTY WZORZEC, a nie "zero w kodzie" — bramka musialaby wtedy przepuscic wszystko.
for para in "tabel:$TABEL" "statusow:$STATUSOW" "rodzajow:$RODZAJOW" "testow:$TESTOW_SH" \
            "retencja:$RETENCJA" "okno:$OKNO" "php:$PHP_MIN" \
            "limit-mail:$LIMIT_MAIL" "limit-serial:$LIMIT_SERIAL" "limit-ip:$LIMIT_IP"; do
	nazwa="${para%%:*}"; wartosc="${para##*:}"
	case "$wartosc" in
		''|0) echo "  BLAD BRAMKI: licznik '$nazwa' zwrocil [$wartosc] — wzorzec przestal pasowac do kodu."
		      echo "  Napraw wzorzec w tym pliku, zanim uwierzysz wynikowi."; exit 2 ;;
	esac
done

echo "Z KODU: tabel=$TABEL statusow=$STATUSOW rodzajow=$RODZAJOW testow-diagnostyki=$TESTOW_SH"
echo "        retencja=$RETENCJA dni, okno potwierdzenia=$OKNO h, PHP min=$PHP_MIN"
echo "        limity zgloszen: e-mail=$LIMIT_MAIL/dobe, serial=$LIMIT_SERIAL/dobe, IP=$LIMIT_IP/10min"
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

# ⚠️ `sprawdz` odpowiada na pytanie „czy poprawna liczba GDZIEKOLWIEK jest" — jedno trafienie
# wystarczy do PASS. To ZA MALO: dokument moze miec poprawna liczbe w jednym akapicie i bledna
# w drugim, a bramka i tak swieci na zielono (zlapane 31.07 audytem koncowym: README mowil
# „czternascie testow" w linii 37 i „42 testy" w linii 193 — kontrola przechodzila).
# Ponizsza funkcja odpowiada na pytanie odwrotne: „czy w dokumencie NIE MA innej liczby".
sprawdz_bez_sprzecznych() { # $1=opis  $2=rzeczownik(regex)  $3=poprawna-liczba  $4..=pliki
	local opis="$1" rzeczownik="$2" poprawna="$3"; shift 3
	local zle=""
	for n in $( grep -ohiE "[0-9]+ ${rzeczownik}" "$@" 2>/dev/null | grep -oE "^[0-9]+" | sort -u ); do
		[ "$n" = "$poprawna" ] || zle="$zle $n"
	done
	if [ -n "$zle" ]; then
		bad "$opis — w dokumencie stoja TEZ inne liczby:$zle (z kodu: $poprawna)"
	else
		ok "$opis"
	fi
}

# liczby slownie ORAZ cyfra — dokumenty klienta pisza slownie
sprawdz "README: liczba tabel = $TABEL" "$TABEL tabel" README.md dokumentacja-techniczna/DATABASE.md
sprawdz "README: liczba statusow = $STATUSOW" "$STATUSOW (konfigurowalnych )?status" README.md
sprawdz "README: liczba rodzajow spraw = $RODZAJOW" "$RODZAJOW rodzaj" README.md
case "$TESTOW_SH" in
	10) SLOWNIE="dziesięć" ;; 11) SLOWNIE="jedenaście" ;; 12) SLOWNIE="dwanaście" ;;
	13) SLOWNIE="trzynaście" ;; 14) SLOWNIE="czternaście" ;; 15) SLOWNIE="piętnaście" ;;
	16) SLOWNIE="szesnaście" ;; 17) SLOWNIE="siedemnaście" ;; 18) SLOWNIE="osiemnaście" ;;
	*) SLOWNIE="__brak_mapy__" ;;
esac
sprawdz "README: liczba testow diagnostyki = $TESTOW_SH" "$SLOWNIE testów|$TESTOW_SH testów" README.md
sprawdz "ADMIN.md: liczba testow diagnostyki = $TESTOW_SH" "$TESTOW_SH testów" dla-klienta/instrukcje/ADMIN.md
# Kontrola spojnosci (nie tylko istnienia) — patrz komentarz przy `sprawdz_bez_sprzecznych`.
# ⚠️ Celowo TYLKO dla liczby testow diagnostyki, a nie dla kazdej liczby w dokumentach:
# ta sama liczba potrafi poprawnie znaczyc co innego w dwoch akapitach (DATABASE.md cytuje
# „4 tabele" ze specyfikacji klienta, a system ma ich 16 — obie liczby sa prawdziwe).
# Uniwersalna bramka na wszystkie liczby dawalaby falszywe alarmy i zostalaby wylaczona.
sprawdz_bez_sprzecznych "README: brak sprzecznej liczby testow diagnostyki" "test(ów|y|ow|u)?" "$TESTOW_SH" README.md
sprawdz_bez_sprzecznych "ADMIN.md: brak sprzecznej liczby testow diagnostyki" "test(ów|y|ow|u)?" "$TESTOW_SH" dla-klienta/instrukcje/ADMIN.md
sprawdz "INSTRUKCJA: retencja porzuconych = $RETENCJA dni" "$RETENCJA dniach|$RETENCJA dni" dla-klienta/INSTRUKCJA-KLIENTA.md
# ⛔ TA KONTROLA PILNOWALA BLEDU (2.34). Zadala, zeby w instrukcji KLIENTA stalo
# „72 godzin" — a jedynym miejscem, gdzie ta liczba tam wystepowala, bylo zdanie
# NIEPRAWDZIWE: „link potwierdzajacy jest wazny 72 godziny". Bramka trzymala wiec
# blad w miejscu: poprawienie zdania zapalalo ja na czerwono. Okno potwierdzenia
# jest liczba WEWNETRZNA — klientowi potrzebna jest waznosc LINKU. Kontrola pyta
# teraz o nia, wiec liczy sie tak samo, ale sprawdza rzecz prawdziwa.
sprawdz "INSTRUKCJA: waznosc linku = $TTL h" "$TTL godzin" dla-klienta/INSTRUKCJA-KLIENTA.md
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

# ── progi ochrony formularza: dokumenty podaja je LICZBOWO, wiec musza sie zgadzac ──
# Powod: obsluga mowi klientowi „mozesz wyslac 3 na dobe". Zmiana progu w kodzie bez
# poprawki instrukcji = klient dostaje nieprawdziwa informacje od pracownika serwisu.
sprawdz "INSTRUKCJA: limit na e-mail = $LIMIT_MAIL/dobe" "\*\*$LIMIT_MAIL zgłoszenia na dobę\*\*" dla-klienta/INSTRUKCJA-KLIENTA.md
sprawdz "INSTRUKCJA: limit na serial = $LIMIT_SERIAL/dobe" "\*\*$LIMIT_SERIAL na dobę\*\*" dla-klienta/INSTRUKCJA-KLIENTA.md
sprawdz "INSTRUKCJA: limit na IP = $LIMIT_IP/10 min" "\*\*$LIMIT_IP w ciągu 10 minut\*\*" dla-klienta/INSTRUKCJA-KLIENTA.md
sprawdz "KLIENT.md: limit na e-mail = $LIMIT_MAIL/dobe" "\*\*$LIMIT_MAIL zgłoszenia na dobę\*\*" dla-klienta/instrukcje/KLIENT.md
# Wzorzec wiaze prog z JEGO NAZWA (wiersz tabeli), zeby nie zaliczyc luznej liczby
# stojacej gdziekolwiek indziej w dokumencie.
sprawdz "SECURITY.md: limit na e-mail = $LIMIT_MAIL" "na adres e-mail.{0,30}$LIMIT_MAIL zgłosze" dokumentacja-techniczna/SECURITY.md
sprawdz "SECURITY.md: limit na serial = $LIMIT_SERIAL" "na numer seryjny.{0,30}$LIMIT_SERIAL zgłosze" dokumentacja-techniczna/SECURITY.md
sprawdz "SECURITY.md: limit na IP = $LIMIT_IP" "na adres IP.{0,30}$LIMIT_IP zgłosze" dokumentacja-techniczna/SECURITY.md

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

	# ⚠️ Ta sama nieprawda zyje w DWOCH miejscach: w dokumentach i w napisach na ekranach.
	# 29.07 poprawiono dokumenty, ale komunikaty w kodzie dalej kazaly nadac range
	# „Pracownik serwisu" (bez „MP") — bramka ich nie widziala, bo patrzyla tylko na *.md.
	# Zlapane audytem jezyka 31.07. Szukamy nazwy roli w CUDZYSLOWIE DRUKARSKIM, bo tak
	# cytuja ja komunikaty; zwykle zdania w rodzaju „brak pracownikow serwisu" nie sa cytatem
	# nazwy z listy rol i nie moga wywolywac falszywego alarmu.
	ZLE_KOD="$(grep -rn "„$BAZA[\"”]" --include='*.php' mp-service-intake/includes mp-warranty-registry/includes mp-workflow-automator/includes 2>/dev/null \
		| grep -v "„$ROLA[\"”]" || true)"
	if [ -z "$ZLE_KOD" ]; then
		ok "nazwa roli w napisach na ekranach zgodna z panelem: $ROLA"
	else
		bad "komunikat w kodzie cytuje nazwe roli inaczej niz lista rol ($ROLA):"
		echo "$ZLE_KOD" | head -3 | sed 's/^/         /'
	fi
done < <(sed -n "s/^[[:space:]]*'mp_[a-z_]*'[[:space:]]*=>[[:space:]]*'\([^']*\)'.*/\1/p" lib/mp-common/src/Roles.php)

# ── Surowe nazwy stalych z kodu w napisach dla uzytkownika ──────────────────
# Etykieta „Pokaz techniczne (SWEEP_RUN)" pokazywala nazwe stalej PHP wprost na ekranie
# administratora (audyt jezyka 31.07). Nazwy stalych sa dla programisty, nie dla serwisanta.
STALE_W_UI="$(grep -rnoE "(__|_e|esc_html__|esc_html_e|esc_attr__|esc_attr_e)\( '[^']*[A-Z]{3,}_[A-Z]{3,}[^']*'" \
	--include='*.php' mp-service-intake/includes mp-warranty-registry/includes mp-workflow-automator/includes 2>/dev/null || true)"
if [ -z "$STALE_W_UI" ]; then
	ok "zaden napis na ekranie nie pokazuje nazwy stalej z kodu"
else
	bad "napis dla uzytkownika zawiera surowa nazwe stalej z kodu:"
	echo "$STALE_W_UI" | head -3 | sed 's/^/         /'
fi

# ── 2.34: WAZNOSC LINKU potwierdzajacego ────────────────────────────────────
# ⛔ KOD BYL POPRAWNY — to dokumenty klamaly. W module sa DWIE rozne stale:
#   · TOKEN_TTL_HOURS      — ile zyje LINK (ustawia verify_token_expires_at),
#   · CONFIRM_WINDOW_HOURS — okno, w ktorym sprawa jest jeszcze brana pod uwage.
# Trzy zdania dla czlowieka podawaly przy „waznosci linku" te DRUGA liczbe, wiec
# koordynator patrzyl na zgloszenie sprzed trzydziestu godzin i myslal, ze klient
# ma jeszcze czterdziesci dwie. Link juz nie dzialal. Mail do klienta podawal
# liczbe poprawna, bo bierze ja ZE STALEJ — sklamaly wylacznie miejsca wpisane
# recznie. Ta bramka pilnuje, zeby nie wrocily.
DOK_LINK="dla-klienta/INSTRUKCJA-KLIENTA.md dla-klienta/instrukcje/KOORDYNATOR.md"

# Bierzemy liczby ze zdan, ktore mowia JEDNOCZESNIE o linku i o waznosci —
# dzieki temu nie lapiemy poprawnych „72 h" opisujacych okno potwierdzenia.
ZDANIA_LINK=$(grep -ohiE ".*link.*wa[zż]n.*|.*wa[zż]n.*link.*" $DOK_LINK 2>/dev/null)

# ⚠️ PROBA KONTROLNA: zero zdan znaczy „zle szukam", a nie „wszystko dobrze".
# Bez tego bramka swiecilaby na zielono po samej zmianie brzmienia zdania.
if [ -z "$ZDANIA_LINK" ]; then
	bad "waznosc linku: nie znalazlem ANI JEDNEGO zdania o waznosci linku w: $DOK_LINK"
else
	ZLE_TTL=""
	for n in $( printf '%s' "$ZDANIA_LINK" | grep -oE "[0-9]+" | sort -u ); do
		[ "$n" = "$TTL" ] || ZLE_TTL="$ZLE_TTL $n"
	done

	if [ -n "$ZLE_TTL" ]; then
		bad "waznosc linku potwierdzajacego: dokumenty podaja$ZLE_TTL h, a kod mowi $TTL h (TOKEN_TTL_HOURS)"
	else
		ok "waznosc linku potwierdzajacego = $TTL h zgodna w dokumentach dla czlowieka"
	fi
fi

# Zrodlo pomylki: dokument techniczny podawal obie liczby tak, ze druga czytalo
# sie jak termin waznosci linku. Poprawienie samych instrukcji NIE wystarczy —
# to zdanie wyprodukowaloby blad ponownie.
# ⚠️ Wzorzec URWANY PRZED polskim znakiem („dziala" vs „działa") — wersja z pelnym
# slowem NIGDY by nie trafila, a kontrola swiecilaby na zielono, nic nie sprawdzajac.
if grep -qiE "okno POTWIERDZENIA \(po nim link nie dzia" dokumentacja-techniczna/STATE_MACHINE.md 2>/dev/null; then
	bad "STATE_MACHINE: okno potwierdzenia dalej opisane jako termin waznosci linku (zrodlo pomylki 2.34)"
else
	ok "STATE_MACHINE: okno potwierdzenia nie udaje terminu waznosci linku"
fi


# ── historia zmian modulu opisuje WLASNY modul, nie cudzy (poz. 2.9) ────────
# Wpisy w readme.txt trzech modulow byly IDENTYCZNE: kazdy opisywal poprawke
# ekranu wyjatkow gwarancyjnych i etykiete przycisku „SWEEP_RUN" w rejestrze
# zdarzen, choc kod obu tych rzeczy istnieje wylacznie w po JEDNYM module.
# Kto otwieral historie zmian modulu zgloszen, czytal o cudzych funkcjach.
#
# Kontrola jest WZORCOWA, nie na jeden napis: nazwa stalej z kodu wolno stac
# w historii zmian tylko tego modulu, ktory te stala naprawde ma. Doklada sie
# ja przez dopisanie nazwy do listy STALE_MODULOWE.
STALE_MODULOWE="SWEEP_RUN EXCEPTION_APPLIED"
for MODUL in mp-service-intake mp-warranty-registry mp-workflow-automator; do
	for STALA in $STALE_MODULOWE; do
		if ! grep -qF "$STALA" "$MODUL/readme.txt" 2>/dev/null; then
			continue   # nie opisuje — nie ma czego sprawdzac
		fi
		if grep -rqF "$STALA" "$MODUL/includes" 2>/dev/null; then
			ok "$MODUL/readme.txt opisuje '$STALA' i ta rzecz jest w kodzie TEGO modulu"
		else
			bad "$MODUL/readme.txt opisuje '$STALA', a w kodzie tego modulu tego nie ma (historia zmian opisuje cudzy modul)"
		fi
	done
done

# Druga strona tej samej wady: trzy historie zmian byly BAJT W BAJT takie same.
# Identyczne sekcje znacza, ze co najmniej dwie opisuja cudza robote.
# Porownujemy SAMA sekcje historii zmian, nie caly plik.
sekcja_zmian() { sed -n '/^== Changelog ==/,$p' "$1" 2>/dev/null; }
LINII_HIST=$(sekcja_zmian mp-service-intake/readme.txt | wc -l)
if [ "$LINII_HIST" -lt 10 ]; then
	bad "kontrola historii zmian mierzy PUSTO (sekcja '== Changelog ==' ma $LINII_HIST linii) — sprawdz naglowek w readme.txt"
else
	H_A=$(sekcja_zmian mp-service-intake/readme.txt | md5sum)
	H_B=$(sekcja_zmian mp-warranty-registry/readme.txt | md5sum)
	H_C=$(sekcja_zmian mp-workflow-automator/readme.txt | md5sum)
	if [ "$H_A" = "$H_B" ] || [ "$H_A" = "$H_C" ] || [ "$H_B" = "$H_C" ]; then
		bad "historia zmian jest identyczna w co najmniej dwoch modulach — przeklejona miedzy wtyczkami"
	else
		ok "historia zmian rozna w kazdym z trzech modulow ($LINII_HIST linii w module zgloszen)"
	fi
fi

# ── dokumenty audytu nie moga obiecywac wiecej, niz sprawdzono (poz. 2.43, 2.44) ──
# Poz. 2.43: `ZAKRES-SPRAWDZONY.md` deklarowal „wykonanie na dzialajacym systemie" przy
# pozycjach, ktorych czlowiek w interfejsie zrobic NIE MOGL (odrzucenie z powodem, historia
# produktu) — sprawdzono warstwe danych, a wada siedziala na styku czlowieka z ekranem.
# Do tego w czesci o bezpieczenstwie nie byla NAZWANA kategoria „personel wobec personelu",
# wiec nikt nie mogl zauwazyc, ze jej brakuje.
ZAKRES=audyt/ZAKRES-SPRAWDZONY.md
if grep -q "MIEDZY ROLAMI PERSONELU\|MIĘDZY ROLAMI PERSONELU" "$ZAKRES" 2>/dev/null; then
	ok "ZAKRES-SPRAWDZONY: kategoria personel-wobec-personelu nazwana wprost"
else
	bad "ZAKRES-SPRAWDZONY: brak kategorii personel-wobec-personelu — luka, ktora ukryla poz. 2.24"
fi
if grep -q "WYLACZNIE od strony zaplecza\|WYŁĄCZNIE od strony zaplecza" "$ZAKRES" 2>/dev/null; then
	ok "ZAKRES-SPRAWDZONY: pozycje sprawdzone tylko od zaplecza sa OZNACZONE"
else
	bad "ZAKRES-SPRAWDZONY: nie widac oznaczenia pozycji sprawdzonych wylacznie od zaplecza (poz. 2.43)"
fi

# Poz. 2.44: rubryka „gotowe" ma kryteria BINARNE, a trzy jej zdania tego nie spelnialy.
RUBRYKA=audyt/RUBRYKA-GOTOWE.md
# (a) Dokument twierdzil, ze danych produktu NIE DA SIE edytowac — a kod ma liste pol
#     edytowalnych. Sprawdzamy DOKUMENT WZGLEDEM KODU, nie samego siebie.
if grep -q "EDITABLE_FIELDS" mp-warranty-registry/includes/Repo.php 2>/dev/null; then
	if grep -q "DA SIE edytowac\|DA SIĘ edytować" "$RUBRYKA" 2>/dev/null; then
		ok "RUBRYKA-GOTOWE: zgodna z kodem — dane produktu sa edytowalne i tak to opisuje"
	else
		bad "RUBRYKA-GOTOWE: kod ma EDITABLE_FIELDS, a rubryka nie mowi, ze dane produktu DA SIE edytowac (poz. 2.44a)"
	fi
fi
# (b) i (c): kryteria stojace na niepelnym dowodzie musza byc oznaczone, nie zaliczone.
if grep -q "Chrome, Edge, Firefox" "$RUBRYKA" 2>/dev/null; then
	grep "Chrome, Edge, Firefox" "$RUBRYKA" | grep -q "CZESCIOWO\|CZĘŚCIOWO" \
		&& ok "RUBRYKA-GOTOWE: kryterium przegladarek oznaczone jako czesciowe (Edge nie osobno)" \
		|| bad "RUBRYKA-GOTOWE: kryterium wymienia trzy przegladarki i stoi jako spelnione, choc Edge nie byl osobno (poz. 2.44b)"
fi
if grep -q "35 z 39" "$RUBRYKA" 2>/dev/null; then
	grep "35 z 39" "$RUBRYKA" | grep -q "NIESPELNIONE\|NIESPEŁNIONE" \
		&& ok "RUBRYKA-GOTOWE: cztery niespelnione punkty zamowienia nazwane wprost jako brak dowodu" \
		|| bad "RUBRYKA-GOTOWE: wynik 35 z 39 bez powiedzenia, ze pozostale cztery sa NIESPELNIONE (poz. 2.44c)"
fi

echo
# ── 2.36: liczba kontroli w DOKUMENCIE = liczba pilnowana przez te bramke ───
# `JAKOSC-I-AUDYTY.md` opisuje te bramke z liczby („N kontroli"). Liczba stala tam
# nieaktualna — a to jest DOKLADNIE ta klasa bledu, ktorej ta bramka pilnuje:
# liczba w dokumencie niezgodna z kodem, w dokumencie o tej wlasnie bramce.
# Teraz pilnuje sie sama: zrodlem prawdy jest MIN_KONTROLI, czyli liczba ZMIERZONA.
DOK_JAKOSC=dokumentacja-techniczna/JAKOSC-I-AUDYTY.md
LICZBA_W_DOK=$(grep -ohiE "[0-9]+ kontrol[a-zęąićó]*" "$DOK_JAKOSC" 2>/dev/null | grep -oE "^[0-9]+" | head -1)
if [ -z "$LICZBA_W_DOK" ]; then
	bad "JAKOSC-I-AUDYTY: nie znalazlem ANI JEDNEJ liczby kontroli — wzorzec przestal pasowac (proba kontrolna)"
elif [ "$LICZBA_W_DOK" = "$MIN_KONTROLI" ]; then
	ok "JAKOSC-I-AUDYTY: liczba kontroli w dokumencie ($LICZBA_W_DOK) zgodna z bramka"
else
	bad "JAKOSC-I-AUDYTY: dokument mowi $LICZBA_W_DOK kontroli, a bramka pilnuje $MIN_KONTROLI"
fi

echo
echo "WYNIK: $PASS ok, $FAIL fail"

if [ "$(( PASS + FAIL ))" -lt "$MIN_KONTROLI" ]; then
	echo "  BLAD BRAMKI: wykonalo sie $(( PASS + FAIL )) kontroli, oczekiwane min. $MIN_KONTROLI."
	echo "  Ktoras cicho NIE wystartowala — sprawdz stderr i kolejnosc definicji funkcji."
	exit 2
fi

[ "$FAIL" -eq 0 ]
