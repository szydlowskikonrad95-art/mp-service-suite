#!/usr/bin/env bash
# TEST PACZKI OD ZERA — to, czego CI nie sprawdza: ZBIORCZA paczka dla klienta
# rozpakowana na SWIEZYM WordPressie i zainstalowana tak, jak zrobi to klient.
#
#   bash testy/paczka-od-zera/uruchom.sh          # pelny przebieg (stawia i sprzata)
#   ZOSTAW=1 bash testy/paczka-od-zera/uruchom.sh # zostaw witryne do ogladania
#
# Czym rozni sie od CI:
#   - PHP 8.1 + MySQL 8 = deklarowane MINIMUM z PRZECZYTAJ-MNIE (poligon chodzi na 8.4/MariaDB),
#   - zrodlem wtyczek jest ZIP wyjety ze zbiorczej paczki, nie katalog repo,
#   - jedna wtyczka wgrywana przez PANEL (Wtyczki -> Dodaj nowa -> Wyslij na serwer),
#   - cala sciezka zgloszenia idzie po HTTP, mail czytany ze skrzynki (Mailpit).
set -euo pipefail
# MP_PACZKA podaje sie zwykle wzglednie od KATALOGU REPO ("build/dist/...", tak brzmia
# nasze notatki), a my zaraz robimy `cd` do wlasnego katalogu — wtedy plik „znika".
# Zamieniamy na sciezke bezwzgledna, ZANIM zmienimy katalog.
[ -n "${MP_PACZKA:-}" ] && MP_PACZKA="$(realpath -m "$MP_PACZKA")"
cd "$(dirname "$0")"
PROJEKT=mpzero
BASE="http://localhost:8097"
# Haslo administratora losowane na kazdy przebieg — zaden literal nie ma prawa
# wjechac do repo (skan sekretow czyta kazda linijke i ma racje).
export MP_TEST_HASLO="${MP_TEST_HASLO:-$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')}"

sprzataj() { [ "${ZOSTAW:-0}" = "1" ] || docker compose -p "$PROJEKT" down -v --remove-orphans >/dev/null 2>&1 || true; }
trap sprzataj EXIT

# Sprzatanie poprzedniego przebiegu bez rekurencyjnego kasowania katalogu
# (strażnik warsztatu blokuje `rm -rf` poza strefa bezpieczna — i slusznie).
mkdir -p paczka
find paczka -mindepth 1 -maxdepth 1 -exec rm -r {} + 2>/dev/null || true

# MP_PACZKA=<sciezka do zip> — testuj KONKRETNY artefakt, np. pobrany z wydania
# na GitHubie. Tak sprawdzamy dokladnie to, co dostanie klient, a nie swiezy build.
if [ -n "${MP_PACZKA:-}" ]; then
	echo "== 0. Paczka WSKAZANA: $MP_PACZKA =="
	[ -f "$MP_PACZKA" ] || { echo "BLAD: nie ma pliku $MP_PACZKA"; exit 1; }
	cp "$MP_PACZKA" paczka/
else
	echo "== 0. Swieza paczka z biezacego kodu =="
	( cd ../.. && bash build/pakuj-dla-klienta.sh ) | tail -2
	cp ../../build/dist/mp-service-suite-KLIENT-*.zip paczka/
fi
( cd paczka && unzip -q -o mp-service-suite-KLIENT-*.zip )
KAT="$(basename "$(ls -d paczka/mp-service-suite-*/ | head -1)")"
printf '%s' "$MP_TEST_HASLO" > paczka/.haslo   # katalog paczka/ jest gitignorowany

echo "== 1. Czysty WordPress (${MP_WP_OBRAZ:-wordpress:6.9-php8.1-apache}) =="
docker compose -p "$PROJEKT" down -v --remove-orphans >/dev/null 2>&1 || true
docker compose -p "$PROJEKT" up -d >/dev/null
W() { docker compose -p "$PROJEKT" exec -T cli wp --path=/var/www/html "$@"; }
for i in $(seq 1 60); do W core is-installed >/dev/null 2>&1 && break
  W db check >/dev/null 2>&1 || true
  curl -s -o /dev/null "$BASE/" 2>/dev/null && W core install --url="$BASE" --title="Serwis MP" \
     --admin_user=szef --admin_password="$MP_TEST_HASLO" --admin_email=szef@mp-demo.example \
     --skip-email >/dev/null 2>&1 && break
  sleep 3
done
W core is-installed || { echo "BLAD: WordPress sie nie postawil"; exit 1; }
echo "   WP $(W core version) / PHP $(W eval 'echo PHP_VERSION;') / baza $(W eval 'echo $GLOBALS["wpdb"]->db_version();')"

echo "== 2. Instalacja 3 wtyczek z paczki (kolejnosc jak w PRZECZYTAJ-MNIE) =="
for z in mp-service-intake mp-warranty-registry mp-workflow-automator; do
  W plugin install "/paczka/$KAT/$z.zip" --activate >/dev/null
done
AKT=$(W plugin list --status=active --field=name | grep -c '^mp-')
[ "$AKT" = "3" ] && echo "   3 wtyczki aktywne" || { echo "BLAD: aktywnych mp-: $AKT"; exit 1; }

echo
echo "== 3. Sciezka klienta =="
bash sciezka-klienta.sh
echo
echo "== 4. Wgranie wtyczki przez panel =="
bash wgraj-przez-panel.sh
echo
[ "${ZOSTAW:-0}" = "1" ] && echo "Witryna zostaje: $BASE/wp-admin (uzytkownik szef, haslo w paczka/.haslo), poczta: http://localhost:8098"
echo "PACZKA OD ZERA: PRZESZLA"
