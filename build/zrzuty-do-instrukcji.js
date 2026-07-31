#!/usr/bin/env node
/**
 * Zrzuty ekranu do instrukcji klienta — jedną komendą, zamiast ręcznego klikania.
 *
 * Po co: zdjęcia w instrukcjach starzeją się przy KAŻDEJ zmianie interfejsu
 * (plakietki statusów, kolumny, etykiety pól). Odtwarzane ręcznie raz na jakiś
 * czas rozjeżdżają się z produktem — klient widzi na zdjęciu inny ekran, niż ma
 * przed sobą, i przestaje ufać całej instrukcji. Skoro diagramy i PDF-y powstają
 * maszynowo (`render-diagramy.py`, `pakuj-dla-klienta.sh`), zdjęcia też mają.
 *
 * Zrzut robi PRAWDZIWA przeglądarka (Chromium), więc łapie też to, czego nie
 * widać w HTML-u: błędy konsoli i nieudane żądania. Każdy taki błąd jest
 * raportowany, a kod wyjścia 1 nie pozwala wpuścić do paczki zdjęcia ekranu,
 * który się sypie.
 *
 * ⛔ ZERO danych w kodzie: adres i hasło przychodzą ze zmiennych środowiskowych,
 * żeby nic z naszego środowiska nie wjechało do repozytorium klienta.
 *
 * UŻYCIE:
 *   MP_BASE=https://adres MP_USER=admin MP_PASS=... node build/zrzuty-do-instrukcji.js [nazwa...]
 *   MP_CASE_ID=7   — konkretna sprawa na zrzucie karty (domyślnie: pierwsza z listy)
 *   Bez argumentów robi komplet; z argumentami tylko wskazane zrzuty, np.:
 *   node build/zrzuty-do-instrukcji.js admin-02-karta-sprawy 02-formularz-pusty
 */
module.paths.push('/usr/lib/node_modules');
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const BASE = (process.env.MP_BASE || '').replace(/\/$/, '');
const USER = process.env.MP_USER || '';
const PASS = process.env.MP_PASS || '';
const CASE_ID = process.env.MP_CASE_ID || '';

if (!BASE || !USER || !PASS) {
  console.error('Brakuje MP_BASE / MP_USER / MP_PASS w środowisku.');
  process.exit(2);
}

const KATALOG = path.join(__dirname, '..', 'dla-klienta', 'instrukcje', 'zdjecia');
const SZEROKOSC = 1440;

/**
 * Plik przykładowy do wgrania na zrzucie wypełnionego formularza.
 * Powstaje w locie — nie trzymamy w repozytorium zdjęcia-atrapy.
 */
function plikPrzykladowy() {
  const cel = path.join(require('os').tmpdir(), 'tabliczka-znamionowa.jpg');
  // PRAWDZIWY (choć malutki) JPEG. Atrapa z samym nagłówkiem przechodziła
  // kontrolę typu, ale GD nie potrafił jej odczytać przy usuwaniu danych EXIF —
  // w logu zostawały ostrzeżenia, a w sprawie załącznik, którego nie da się otworzyć.
  fs.writeFileSync(cel, Buffer.from('/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYwLjMxLjEwMgD/2wBDAAgYGBwYHCEhISEhISckJygoKCcnJycoKCgrKyszMzMrKysoKCsrMDAzMzc5NzQ0MzQ5OTw8PEhIRUVUVFdnZ3z/xABLAAEBAAAAAAAAAAAAAAAAAAAABAEBAAAAAAAAAAAAAAAAAAAAABABAAAAAAAAAAAAAAAAAAAAABEBAAAAAAAAAAAAAAAAAAAAAP/AABEIADAAMAMBIgACEQADEQD/2gAMAwEAAhEDEQA/AKwAAAAAAAAAAAAAAAAAf//Z', 'base64'));
  return cel;
}

// Lista zrzutów. `akcje` dostaje stronę Playwrighta — tu wypełniamy formularz,
// wybieramy kategorię itd., żeby zdjęcie pokazywało ekran W UŻYCIU, a nie pusty.
const ZRZUTY = [
  {
    nazwa: 'admin-01-sprawy',
    url: () => `${BASE}/wp-admin/admin.php?page=mp-cases`,
  },
  {
    nazwa: 'admin-02-karta-sprawy',
    url: async (page) => {
      if (CASE_ID) {
        return `${BASE}/wp-admin/admin.php?page=mp-cases&case_id=${CASE_ID}`;
      }
      // Bez wskazanej sprawy bierzemy pierwszą z listy — zrzut ma zawsze powstać.
      await page.goto(`${BASE}/wp-admin/admin.php?page=mp-cases`, { waitUntil: 'networkidle' });
      const href = await page.locator('a[href*="case_id="]').first().getAttribute('href');
      return new URL(href, BASE).toString();
    },
  },
  { nazwa: 'admin-03-niepotwierdzone', url: () => `${BASE}/wp-admin/admin.php?page=mp-intake-unverified` },
  { nazwa: 'admin-04-rejestr', url: () => `${BASE}/wp-admin/admin.php?page=mp-registry` },
  { nazwa: 'admin-05-import-csv', url: () => `${BASE}/wp-admin/admin.php?page=mp-registry-import` },
  {
    // Ekran poprawiania danych produktu. Bez wskazanego ID bierzemy pierwszy wpis
    // z odnosnikiem „popraw dane" — zrzut ma powstac na kazdej instancji z danymi.
    nazwa: 'admin-04b-popraw-produkt',
    url: async (page) => {
      await page.goto(`${BASE}/wp-admin/admin.php?page=mp-registry`, { waitUntil: 'networkidle' });
      const href = await page.locator('a[href*="edit="]').first().getAttribute('href');
      return new URL(href, BASE).toString();
    },
  },
  {
    // Wyjatki dotycza ZAWSZE konkretnego produktu. Wejscie na sam adres ekranu, bez
    // parametru `product`, pokazuje wylacznie podpowiedz „Wybierz produkt z listy" —
    // taki zrzut trafil do instrukcji i ilustrowal funkcje PUSTA strona. Dlatego
    // wchodzimy tak, jak wchodzi administrator: z listy produktow, odnosnikiem
    // „wyjatki" w kolumnie Akcje. Preferujemy produkt, ktory JUZ MA wyjatek
    // (plakietka `.mp-badge-exception`), zeby zdjecie pokazywalo tresc, nie sam formularz.
    nazwa: 'admin-06-wyjatki',
    url: async (page) => {
      if (process.env.MP_PRODUCT_ID) {
        return `${BASE}/wp-admin/admin.php?page=mp-registry-exceptions&product=${process.env.MP_PRODUCT_ID}`;
      }
      await page.goto(`${BASE}/wp-admin/admin.php?page=mp-registry`, { waitUntil: 'networkidle' });
      const zWyjatkiem = page.locator('tr:has(.mp-badge-exception) a[href*="mp-registry-exceptions"]').first();
      const dowolny = page.locator('a[href*="mp-registry-exceptions"]').first();
      const wybrany = (await zWyjatkiem.count()) > 0 ? zWyjatkiem : dowolny;
      if ((await wybrany.count()) === 0) {
        throw new Error('Brak produktu w rejestrze — nie ma z czego zrobic zrzutu wyjatkow.');
      }
      return new URL(await wybrany.getAttribute('href'), BASE).toString();
    },
  },
  { nazwa: 'admin-07-automatyzacje', url: () => `${BASE}/wp-admin/admin.php?page=mp-automator` },
  {
    nazwa: '02-formularz-pusty',
    rozszerzenie: 'jpg',
    url: () => process.env.MP_FORM_URL,
    wyloguj: true,
    kadrDo: '.mp-intake',
  },
  {
    nazwa: '03-formularz-wypelniony-zalacznik',
    rozszerzenie: 'jpg',
    url: () => process.env.MP_FORM_URL,
    wyloguj: true,
    kadrDo: '.mp-intake',
    // Kategoria AGD: pokazuje WYMAGANY załącznik (P1.2 z kartki) — dokładnie to,
    // czego instrukcja klienta uczy w akapicie o kategoriach.
    akcje: async (page) => {
      await page.selectOption('#mp-f-kind', 'reklamacja');
      await page.selectOption('#mp-f-category', 'agd');
      await page.fill('#mp-f-email', 'anna.kowalska@example.com');
      await page.fill('#mp-f-serial', 'AGD-2024-118834');
      await page.fill('#mp-f-purchase_document', 'FV/2026/03/118');
      await page.fill('#mp-f-purchase_date', '2026-03-14');
      await page.fill('#mp-f-issue_description', 'Odkurzacz po miesiącu przestał trzymać moc ssania, przy pracy słychać piszczenie.');
      await page.setInputFiles('#mp-f-mp_files', plikPrzykladowy());
      await page.check('#mp-f-consent');
    },
  },
  {
    nazwa: '13-formularz-dynamiczny-naprawa',
    rozszerzenie: 'jpg',
    url: () => process.env.MP_FORM_URL,
    wyloguj: true,
    kadrDo: '.mp-intake',
    // Rodzaj „naprawa" ma mniej pól niż reklamacja — o tym mówi instrukcja
    // („przy innym rodzaju sprawy formularz wygląda inaczej — to celowe").
    akcje: async (page) => {
      await page.selectOption('#mp-f-kind', 'naprawa');
      await page.selectOption('#mp-f-category', 'elektronarzedzia');
      await page.fill('#mp-f-email', 'anna.kowalska@example.com');
      await page.fill('#mp-f-serial', 'ETN-2025-004120');
      await page.fill('#mp-f-issue_description', 'Wkrętarka nie ładuje się do końca — dioda miga na czerwono.');
    },
  },
];

(async () => {
  const wybrane = process.argv.slice(2);
  const doZrobienia = wybrane.length ? ZRZUTY.filter((z) => wybrane.includes(z.nazwa)) : ZRZUTY;

  if (!doZrobienia.length) {
    console.error(`Nie znam takich zrzutów: ${wybrane.join(', ')}`);
    process.exit(2);
  }

  // `--lang=pl-PL` NIE jest ozdobą: bez tego pola typu `date` rysują się po
  // amerykańsku (mm/dd/yyyy), a klient na zdjęciu w instrukcji zobaczyłby inny
  // format daty niż ma na ekranie.
  const browser = await chromium.launch({ args: ['--lang=pl-PL,pl'], env: { ...process.env, LANG: 'pl_PL.UTF-8', LANGUAGE: 'pl_PL' } });
  const kontekst = await browser.newContext({ viewport: { width: SZEROKOSC, height: 900 }, locale: 'pl-PL' });

  // Logowanie RAZ, przez prawdziwy formularz — sesja starcza na wszystkie ekrany.
  const logowanie = await kontekst.newPage();
  await logowanie.goto(`${BASE}/wp-login.php`, { waitUntil: 'domcontentloaded' });
  await logowanie.fill('#user_login', USER);
  await logowanie.fill('#user_pass', PASS);
  await Promise.all([logowanie.waitForNavigation({ waitUntil: 'networkidle' }), logowanie.click('#wp-submit')]);
  const zalogowany = await logowanie.locator('#wpadminbar').count();
  await logowanie.close();

  if (!zalogowany) {
    console.error('Nie udało się zalogować — sprawdź MP_USER / MP_PASS.');
    await browser.close();
    process.exit(2);
  }

  let bledy = 0;

  for (const zrzut of doZrobienia) {
    // Ekrany klienta oglądamy jako GOŚĆ (osobny kontekst bez ciasteczek) —
    // zalogowany admin widzi pasek administracyjny, którego klient nigdy nie ma.
    const ctx = zrzut.wyloguj
      ? await browser.newContext({ viewport: { width: SZEROKOSC, height: 900 }, locale: 'pl-PL' })
      : kontekst;
    const page = await ctx.newPage();
    const problemy = [];

    page.on('console', (m) => m.type() === 'error' && problemy.push(`konsola: ${m.text()}`));
    page.on('requestfailed', (r) => problemy.push(`nieudane żądanie: ${r.url()}`));
    page.on('response', (r) => r.status() >= 400 && problemy.push(`HTTP ${r.status()}: ${r.url()}`));

    const adres = typeof zrzut.url === 'function' ? await zrzut.url(page) : zrzut.url;

    if (!adres) {
      console.error(`  ✗ ${zrzut.nazwa}: brak adresu (czy ustawiony MP_FORM_URL?)`);
      bledy++;
      await page.close();
      continue;
    }

    await page.goto(adres, { waitUntil: 'networkidle' });

    if (zrzut.akcje) {
      await zrzut.akcje(page);
      await page.waitForTimeout(400); // JS formularza przelicza pola i etykiety.
    }

    const plik = path.join(KATALOG, `${zrzut.nazwa}.${zrzut.rozszerzenie || 'png'}`);
    const opcje = zrzut.rozszerzenie === 'jpg'
      ? { path: plik, fullPage: true, type: 'jpeg', quality: 88 }
      : { path: plik, fullPage: true };

    // KADR do wskazanego elementu. Powód nie jest kosmetyczny: pełna strona
    // demonstracyjna ciągnie się do stopki, a w stopce siedzi wizytówka
    // wykonawcy. Instrukcja klienta ma pokazywać JEGO produkt, nie nasz podpis —
    // a tego żadna bramka tekstowa nie wyłapie, bo to obrazek.
    if (zrzut.kadrDo) {
      // Wypełnianie pól przewija stronę (przeglądarka goni za fokusem). Wracamy
      // na górę PRZED pomiarem, inaczej kadr zaczyna się w połowie formularza —
      // a `clip` liczy się we współrzędnych STRONY, nie widocznego ekranu,
      // więc musi iść w parze z `fullPage`.
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.waitForTimeout(250);

      const box = await page.locator(zrzut.kadrDo).first().boundingBox();

      if (!box) {
        console.error(`  ✗ ${zrzut.nazwa}: nie znalazłem elementu do kadru (${zrzut.kadrDo})`);
        bledy++;
        await page.close();
        continue;
      }

      opcje.fullPage = true;
      opcje.clip = { x: 0, y: 0, width: SZEROKOSC, height: Math.ceil(box.y + box.height + 48) };
    }

    await page.screenshot(opcje);

    const rozmiar = (fs.statSync(plik).size / 1024).toFixed(0);
    console.log(`  ✓ ${zrzut.nazwa} (${rozmiar} kB)`);
    problemy.slice(0, 5).forEach((p) => console.log(`      ⚠ ${p}`));
    bledy += problemy.length ? 1 : 0;

    await page.close();
    if (zrzut.wyloguj) {
      await ctx.close();
    }
  }

  await browser.close();

  if (bledy) {
    console.error(`\nZrzuty powstały, ale ${bledy} ekran(y) zgłaszały błędy — obejrzyj je przed pakowaniem.`);
    process.exit(1);
  }

  console.log('\nKomplet zrzutów gotowy, zero błędów na stronach.');
})();
