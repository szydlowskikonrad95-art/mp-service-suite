#!/usr/bin/env bash
# ZYWY DOWOD 2.57: komunikat o bledzie prowadzi do KONKRETNEGO POLA.
#
# ⭐ NAJPIERW CO PRODUKT ROBI DOBRZE I CZEGO NIE RUSZAMY: komunikat ma `role="alert"`,
# jest ogloszony, a skrypt PRZENOSI NA NIEGO FOKUS po powrocie strony (obszar
# `aria-live` nie oglasza tresci obecnej juz przy wczytaniu — autor to wiedzial
# i obszedl). Dzial audytu WYCOFAL zarzut „fokus nie idzie na blad" i nazwal to
# mocna strona. Punkt 25 standardu byl SPELNIONY.
#
# BUG (to, co zostaje): obsluga bledow byla zrobiona w POLOWIE.
#  1. `aria-invalid` nie wystepowalo w module ANI RAZU — czytnik ekranu oglaszal
#     podsumowanie, ale przy samym polu nie mowil nic. Osoba idaca tabulatorem
#     musiala zgadywac, ktore pole poprawic.
#  2. Podsumowanie bylo zwyklym akapitem BEZ listy i BEZ odsylaczy do pol.
#  3. Bramki byly SEKWENCYJNE — przy pustym formularzu klient krazyl co najmniej
#     trzy razy (zgoda → zalacznik → pola), choc wszystkie braki byly znane od razu.
#
# ⛔ PULAPKA POMIAROWA, ktora raz juz odwrocila wynik audytu: wyslanie formularza
# SZYBCIEJ NIZ 2 SEKUNDY od otwarcia strony jest traktowane jak robot i dostaje
# CELOWO NEUTRALNY komunikat. Skrypt klikajacy natychmiast zmierzy OCHRONE, nie
# walidacje, i zamelduje wade tam, gdzie dziala zabezpieczenie. Dlatego czekamy.
#
# Chodzi na poligonie i w CI (e2e-import). Exit 0 = OK.
set -u

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  OK  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

BASE="${MP_BASE:-http://127.0.0.1:8080}"
JAR="$(mktemp)"
cget() { curl -sS --max-time 25 -c "$JAR" -b "$JAR" "$@"; }

STRONA=$(wp option get mp_intake_form_page_id 2>/dev/null | tr -d '[:space:]')
SCIEZKA=$(wp post url "$STRONA" 2>/dev/null | sed 's#^https\?://[^/]*##')

HTML=$(cget "$BASE$SCIEZKA")
NONCE=$(printf '%s' "$HTML" | grep -o 'name="_mp_nonce" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//')

[ -n "$NONCE" ] \
	&& ok "formularz wczytany, mam znacznik sesji" \
	|| bad "nie udalo sie wczytac formularza z $BASE$SCIEZKA — test nic nie dowiedzie"

# ⛔ Znacznik czasu STARSZY o 5 s: inaczej wpadamy w pulapke antyspamowa i mierzymy
# ochrone zamiast walidacji (patrz naglowek).
cget -o /dev/null \
	-F "action=mp_intake_submit" -F "_mp_nonce=$NONCE" \
	-F "mp_ts=$(( $(date +%s) - 5 ))" \
	-F "kind=reklamacja" -F "email=" -F "customer_name=" \
	-F "serial=" -F "purchase_document=" -F "purchase_date=" -F "issue_description=" \
	"$BASE/wp-admin/admin-post.php" >/dev/null 2>&1

# Strona powrotna — dokladnie to, co zobaczy czlowiek.
POWROT=$(cget "$BASE$SCIEZKA")

# ── 1. SEDNO: podsumowanie PROWADZI DO POL (lista odsylaczy) ───────────────
LINKI=$(printf '%s' "$POWROT" | grep -o 'href="#mp-f-[a-z_]*"' | sort -u)
ILE_LINKOW=$(printf '%s' "$LINKI" | grep -c 'mp-f-' || true)

[ "${ILE_LINKOW:-0}" -ge 1 ] 2>/dev/null \
	&& ok "podsumowanie bledow prowadzi do pol ($ILE_LINKOW odsylaczy)" \
	|| bad "podsumowanie nie ma ZADNEGO odsylacza do pola (to jest wada 2.57)"

# ── 2. Odsylacz nie moze prowadzic DONIKAD ────────────────────────────────
# Odsylacz wskazujacy na nieistniejacy identyfikator jest GORSZY niz jego brak:
# czlowiek klika i nic sie nie dzieje.
MARTWE=""
for l in $LINKI; do
	CEL=$(printf '%s' "$l" | sed 's/href="#//;s/"//')
	printf '%s' "$POWROT" | grep -q "id=\"$CEL\"" || MARTWE="$MARTWE $CEL"
done

[ -z "$MARTWE" ] \
	&& ok "kazdy odsylacz z podsumowania trafia w istniejace pole" \
	|| bad "odsylacze prowadza DONIKAD:$MARTWE"

# ── 3. Pole z bledem oznaczone dla CZYTNIKA EKRANU ────────────────────────
ILE_INVALID=$(printf '%s' "$POWROT" | grep -o 'aria-invalid="true"' | grep -c . || true)

[ "${ILE_INVALID:-0}" -ge 1 ] 2>/dev/null \
	&& ok "pola z bledem maja aria-invalid ($ILE_INVALID)" \
	|| bad "ZADNE pole nie jest oznaczone jako bledne dla czytnika ekranu (to jest wada 2.57)"

# ── 4. WSZYSTKIE braki wracaja W JEDNYM przebiegu ─────────────────────────
# Pusty formularz ma wiecej niz jeden brak. Przy bramkach sekwencyjnych wracal
# tylko PIERWSZY, wiec klient krazyl. Sprawdzamy, czy wrocilo ich kilka naraz.
[ "${ILE_LINKOW:-0}" -ge 2 ] 2>/dev/null \
	&& ok "pusty formularz zglasza WSZYSTKIE braki naraz ($ILE_LINKOW) — koniec krazenia" \
	|| bad "wrocil tylko $ILE_LINKOW brak — bramki dalej sekwencyjne, klient krazy"

# ── 5. CO ZOSTAJE NIETKNIETE: komunikat dalej jest ogloszany ──────────────
# Kontrola-straznik, zeby naprawa nie zabrala tego, co produkt mial dobrze.
printf '%s' "$POWROT" | grep -q 'role="alert"' \
	&& ok "podsumowanie dalej ma role=alert (mocna strona produktu zachowana)" \
	|| bad "naprawa zabrala komunikatowi role=alert — pogorszenie, nie poprawa"

# ── 6. Stan „to trwa" jest w warstwie klienckiej ──────────────────────────
# Przycisk ma sie zmienic po klknieciu; napis idzie z PHP (tlumaczenie), nie z kodu skryptu.
printf '%s' "$POWROT" | grep -q 'sendingLabel' \
	&& ok "napis stanu „trwa" przekazany do warstwy klienckiej" \
	|| bad "brak napisu stanu „trwa" — klient nie wie, czy wysylka idzie"

rm -f "$JAR"

echo ""
echo "WYNIK 2.57: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
