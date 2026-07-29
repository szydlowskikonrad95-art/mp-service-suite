#!/usr/bin/env node
/**
 * Zrzuty ŚCIEŻKI KLIENTA do instrukcji — jednym przebiegiem, w kolejności,
 * w jakiej klient naprawdę przechodzi przez system.
 *
 * Po co osobno od `zrzuty-do-instrukcji.js`: te ekrany nie są adresami, tylko
 * KROKAMI. Panelu nie da się otworzyć bez potwierdzenia zgłoszenia, a potwierdzenia
 * bez linku z e-maila. Robione ręcznie kończyły się tym, że część zdjęć była
 * z jednego przebiegu, część z innego — stąd w paczce dwa różne opisy pokazywały
 * bajtowo TEN SAM obrazek (10 i 11).
 *
 * ⚠️ E-mail renderujemy z TREŚCI wiadomości, nie z okna narzędzia pocztowego.
 * Poprzedni zrzut pokazywał interfejs Mailpita (nasz łapacz poczty z testów) —
 * klient dostawał w instrukcji zdjęcie programu, którego nigdy nie zobaczy.
 *
 * ⛔ Niczego nie kasujemy: ekran RODO zatrzymujemy NA POTWIERDZENIU, bez kliknięcia.
 *
 * UŻYCIE:
 *   MP_BASE=https://adres MP_PANEL=https://adres/panel-zgloszen/ \
 *   MP_FORM_URL=https://adres/zgloszenie-serwisowe/ node build/zrzuty-sciezka-klienta.js
 *   MP_MAILPIT=http://127.0.0.1:8091   (domyślnie)
 */
module.paths.push('/usr/lib/node_modules');
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const BASE = (process.env.MP_BASE || '').replace(/\/$/, '');
const FORM = process.env.MP_FORM_URL || `${BASE}/zgloszenie-serwisowe/`;
const PANEL = process.env.MP_PANEL || `${BASE}/panel-zgloszen/`;
const MAILPIT = (process.env.MP_MAILPIT || 'http://127.0.0.1:8091').replace(/\/$/, '');
const KATALOG = path.join(__dirname, '..', 'dla-klienta', 'instrukcje', 'zdjecia');
const SZEROKOSC = 1440;

// Dane demo: człowiek, nie „test1@example.com". Numer seryjny musi istnieć
// w rejestrze, inaczej ekrany pokażą „brak danych" zamiast gwarancji.
const KLIENT = {
  email: process.env.MP_KLIENT_EMAIL || 'anna.nowak@example.com',
  serial: process.env.MP_SERIAL || 'SN-AGD-2001',
  dokument: process.env.MP_DOKUMENT || 'FV/2026/0155',
  data: process.env.MP_DATA_ZAKUPU || '2026-02-15',
  opis: 'Czajnik wyłącza się po kilkunastu sekundach i nie dogrzewa wody do końca.',
};

if (!BASE) {
  console.error('Brakuje MP_BASE.');
  process.exit(2);
}

/** Załącznik wymagany dla kategorii AGD (P1.2) — powstaje w locie. */
function plikPrzykladowy() {
  const cel = path.join(require('os').tmpdir(), 'tabliczka-znamionowa.jpg');
  // PRAWDZIWY (choć malutki) JPEG. Atrapa z samym nagłówkiem przechodziła
  // kontrolę typu, ale GD nie potrafił jej odczytać przy usuwaniu danych EXIF —
  // w logu zostawały ostrzeżenia, a w sprawie załącznik, którego nie da się otworzyć.
  fs.writeFileSync(cel, Buffer.from('/9j/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYwLjMxLjEwMgD/2wBDAAgYGBwYHCEhISEhISckJygoKCcnJycoKCgrKyszMzMrKysoKCsrMDAzMzc5NzQ0MzQ5OTw8PEhIRUVUVFdnZ3z/xABLAAEBAAAAAAAAAAAAAAAAAAAABAEBAAAAAAAAAAAAAAAAAAAAABABAAAAAAAAAAAAAAAAAAAAABEBAAAAAAAAAAAAAAAAAAAAAP/AABEIADAAMAMBIgACEQADEQD/2gAMAwEAAhEDEQA/AKwAAAAAAAAAAAAAAAAAf//Z', 'base64'));
  return cel;
}

/**
 * Ostatnia wiadomość do wskazanego adresu (z łapacza poczty).
 *
 * Pobieramy z Node'a, NIE z przeglądarki: strona chodzi po HTTPS, a łapacz
 * poczty po HTTP na localhoście — przeglądarka blokuje takie żądanie
 * jako mieszaną treść i zwraca gołe „Failed to fetch".
 */
async function ostatniMail(_page, adres) {
  const lista = await (await fetch(`${MAILPIT}/api/v1/messages?limit=25`)).json();
  const wpis = (lista.messages || []).find((m) => JSON.stringify(m).includes(adres));

  if (!wpis) {
    return null;
  }

  return (await fetch(`${MAILPIT}/api/v1/message/${wpis.ID}`)).json();
}

/** Pierwszy link o podanym wzorcu w treści wiadomości. */
function linkZMaila(mail, wzorzec) {
  const tresc = `${mail.Text || ''} ${mail.HTML || ''}`;
  const trafienia = tresc.match(new RegExp(`https?://[^\\s"'<>]*${wzorzec}[^\\s"'<>]*`, 'g')) || [];

  return trafienia.length ? trafienia[0].replace(/&amp;/g, '&') : null;
}

(async () => {
  const browser = await chromium.launch({ args: ['--lang=pl-PL,pl'], env: { ...process.env, LANG: 'pl_PL.UTF-8' } });
  const ctx = await browser.newContext({ viewport: { width: SZEROKOSC, height: 900 }, locale: 'pl-PL' });
  const page = await ctx.newPage();
  const zrobione = [];

  /**
   * Czekanie po akcji, która wywołuje przekierowanie.
   *
   * Formularze systemu robią POST na `admin-post.php`, a dopiero stamtąd wraca
   * 302 na stronę docelową. Czekanie na „pierwszą nawigację" kończyło się na
   * `admin-post.php` i zrzut szukał elementów na pustej stronie pośredniej.
   * Czekamy więc na WYCISZENIE sieci, czyli koniec całego łańcucha.
   */
  async function poCzynnosci(dowod) {
    // Czekamy na DOWÓD, że akcja się wykonała — element, którego przed nią nie
    // było. Czekanie „na nawigację" albo „na wyciszenie sieci" wracało za wcześnie:
    // w tej chwili przeglądarka stoi jeszcze na starej stronie, a POST leci
    // dopiero na `admin-post.php`, skąd wraca 302. Zrzut trafiał wtedy na stronę
    // pośrednią.
    if (dowod) {
      await page.waitForSelector(dowod, { timeout: 25000 });
    }

    await page.waitForLoadState('networkidle').catch(() => null);
    await page.waitForTimeout(400);
  }

  /**
   * Zrzut samej SEKCJI panelu.
   *
   * `locator.screenshot()` obcina dokładnie po krawędziach elementu — kadr
   * liczony ręcznie z marginesem zahaczał o nagłówek sąsiedniej sekcji
   * i zdjęcie zaczynało się od uciętego wpół napisu.
   */
  async function zrzutElementu(nazwa, selektor) {
    const el = page.locator(selektor).first();
    const jest = await el.count();

    if (!jest) {
      throw new Error(`${nazwa}: nie ma sekcji ${selektor} na stronie ${page.url()}`);
    }

    await el.scrollIntoViewIfNeeded();
    await page.waitForTimeout(300);

    const plik = path.join(KATALOG, `${nazwa}.jpg`);
    await el.screenshot({ path: plik, type: 'jpeg', quality: 88 });
    zrobione.push(nazwa);
    console.log(`  ✓ ${nazwa}`);
  }

  /** Zrzut: kadr do elementu (bez stopki z wizytówką wykonawcy) albo widoczny ekran. */
  async function zrzut(nazwa, kadrDo) {
    const plik = path.join(KATALOG, `${nazwa}.jpg`);
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(250);

    const opcje = { path: plik, type: 'jpeg', quality: 88 };

    if (kadrDo) {
      // Krótki limit: brak elementu ma dać czytelny komunikat i adres strony,
      // na której naprawdę wylądowaliśmy — a nie 30 s ciszy i gołe „timeout".
      const box = await page
        .locator(kadrDo)
        .first()
        .boundingBox({ timeout: 5000 })
        .catch(() => null);

      if (!box) {
        throw new Error(`${nazwa}: nie ma elementu ${kadrDo} na stronie ${page.url()}`);
      }

      opcje.fullPage = true;
      opcje.clip = { x: 0, y: 0, width: SZEROKOSC, height: Math.ceil(box.y + box.height + 48) };
    }

    await page.screenshot(opcje);
    zrobione.push(`${nazwa} (${(fs.statSync(plik).size / 1024).toFixed(0)} kB)`);
    console.log(`  ✓ ${nazwa}`);
  }

  // ── 1. Strona główna (widoczny ekran — bez schodzenia do stopki) ──────────
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await zrzut('01-strona-glowna');

  // ── 2. Wysłanie zgłoszenia → komunikat ────────────────────────────────────
  async function wypelnijFormularz() {
    await page.selectOption('#mp-f-kind', 'reklamacja');
    await page.selectOption('#mp-f-category', 'agd');
    await page.fill('#mp-f-email', KLIENT.email);
    await page.fill('#mp-f-serial', KLIENT.serial);
    await page.fill('#mp-f-purchase_document', KLIENT.dokument);
    await page.fill('#mp-f-purchase_date', KLIENT.data);
    await page.fill('#mp-f-issue_description', KLIENT.opis);
    await page.setInputFiles('#mp-f-mp_files', plikPrzykladowy());
    await page.check('#mp-f-consent');
  }

  await page.goto(FORM, { waitUntil: 'networkidle' });
  await wypelnijFormularz();
  // Formularz ma pułapkę na boty: wysyłka szybsza niż 2 s = ciche odrzucenie.
  // Przeglądarka wypełnia pola w ułamku sekundy, więc musimy odczekać jak człowiek.
  await page.waitForTimeout(3200);

  // Wysyłka z załącznikiem potrafi utknąć po drodze (publiczny tunel gubi
  // pojedyncze żądania multipart). To nie jest wada produktu, ale przepis ma
  // być powtarzalny — więc próbujemy ponownie zamiast wywracać cały przebieg.
  let wyslane = false;

  for (let proba = 1; proba <= 3 && !wyslane; proba++) {
    await page.click('.mp-intake-submit');
    wyslane = await page
      .waitForSelector('.mp-intake-notice, .mp-intake-error-summary', { timeout: 20000 })
      .then(() => true)
      .catch(() => false);

    if (!wyslane) {
      console.log(`  … próba ${proba} nie doszła (${page.url()}) — powtarzam`);
      await page.goto(FORM, { waitUntil: 'networkidle' });
      await wypelnijFormularz();
      await page.waitForTimeout(3200);
    }
  }

  if (!wyslane) {
    throw new Error('Zgłoszenie nie przeszło po trzech próbach — sprawdź połączenie ze stroną.');
  }

  await poCzynnosci();
  await zrzut('04-po-wyslaniu-komunikat', '.mp-intake');

  // ── 3. E-mail potwierdzający — sama TREŚĆ, bez okna programu pocztowego ───
  await page.waitForTimeout(1500);
  const mail = await ostatniMail(page, KLIENT.email);

  if (!mail) {
    throw new Error('Nie znalazłem e-maila potwierdzającego w łapaczu poczty.');
  }

  const ramka = (m) => `<!doctype html><meta charset=utf-8>
    <style>body{margin:0;background:#eef0f3;font:15px/1.5 -apple-system,Segoe UI,Roboto,sans-serif}
    .koperta{max-width:820px;margin:28px auto;background:#fff;border:1px solid #d7dbe0;border-radius:10px;overflow:hidden}
    .naglowki{padding:18px 24px;border-bottom:1px solid #e6e9ed;background:#fafbfc}
    .naglowki div{margin:2px 0;color:#3c434a}.naglowki .temat{font-size:19px;font-weight:600;color:#111;margin-bottom:8px}
    .tresc{padding:8px 24px 24px}</style>
    <div class=koperta><div class=naglowki>
      <div class=temat>${m.Subject}</div>
      <div><strong>Od:</strong> ${(m.From && m.From.Name) || ''} &lt;${(m.From && m.From.Address) || ''}&gt;</div>
      <div><strong>Do:</strong> ${((m.To && m.To[0] && m.To[0].Address) || '')}</div>
    </div><div class=tresc>${m.HTML || `<pre style="white-space:pre-wrap">${m.Text || ''}</pre>`}</div></div>`;

  await page.setContent(ramka(mail), { waitUntil: 'networkidle' });
  await zrzut('05-skrzynka-mail-potwierdzajacy', '.koperta');

  // ── 4. Potwierdzenie zgłoszenia (2 kroki: strona z przyciskiem → efekt) ───
  const linkPotwierdzenia = linkZMaila(mail, 'mp_intake_verify');

  if (!linkPotwierdzenia) {
    throw new Error('W e-mailu nie ma linku potwierdzającego.');
  }

  await page.goto(linkPotwierdzenia, { waitUntil: 'networkidle' });
  await zrzut('06-ekran-potwierdz-zgloszenie');
  await page.click('button[type=submit]');
  await poCzynnosci();
  await zrzut('07-zgloszenie-potwierdzone');

  // ── 5. Logowanie do panelu (e-mail → link jednorazowy) ────────────────────
  await page.goto(PANEL, { waitUntil: 'networkidle' });
  await zrzut('08-panel-logowanie-mailem');
  await page.fill('input[type=email]', KLIENT.email);
  await page.click('button[type=submit]');
  await poCzynnosci('.mp-account__notice, .mp-intake-notice');

  await page.waitForTimeout(1500);
  const mailPanel = await ostatniMail(page, KLIENT.email);
  const linkPanel = mailPanel ? linkZMaila(mailPanel, 'mp_intake_login') : null;

  if (!linkPanel) {
    throw new Error('Nie znalazłem linku logowania do panelu w poczcie.');
  }

  // Link z e-maila NIE loguje od razu: prowadzi na stronę z przyciskiem
  // „Zaloguj się". To ta sama ochrona, co przy potwierdzaniu zgłoszenia —
  // skanery poczty otwierają linki same, więc samo otwarcie nic nie robi.
  await page.goto(linkPanel, { waitUntil: 'networkidle' });
  await zrzut('09-ekran-zaloguj-sie');
  await page.locator('button[type=submit], input[type=submit]').first().click();
  await poCzynnosci('.mp-account__privacy, .mp-account__case');

  // ── 6. Panel: sprawa, wiadomość, dane + RODO ──────────────────────────────
  // Panel to JEDNA strona z sekcjami, więc każdy podpis w instrukcji dostaje
  // zdjęcie SWOJEJ sekcji. Wcześniej robiono zrzut całego panelu dwa razy —
  // stąd dwa różne opisy pokazywały bajtowo ten sam obrazek.
  await zrzutElementu('11-panel-sprawa-srv10', '.mp-account__case');

  const pole = page.locator('.mp-account__send textarea').first();

  if (await pole.count()) {
    await pole.fill('Dzień dobry, czy potrzebujecie jeszcze zdjęcia tabliczki od spodu? Pozdrawiam, Anna');
    await page.locator('.mp-account__send button[type=submit]').first().click();
    await poCzynnosci('.mp-account__notice, .mp-account__message');
    await zrzutElementu('12-wiadomosc-do-serwisu-wyslana', '.mp-account__case');
  } else {
    console.log('  ⚠ brak formularza wiadomości — pomijam 12');
  }

  await zrzutElementu('10-panel-klienta-dane-rodo', '.mp-account__privacy');

  const rodo = page.locator('.mp-account__privacy-form button[type=submit]').first();

  if (await rodo.count()) {
    await rodo.click();
    await poCzynnosci('.mp-account__privacy-confirm');
    // ⛔ STOP na ekranie potwierdzenia — niczego nie kasujemy.
    await zrzutElementu('14-potwierdzenie-usuniecia-danych', '.mp-account__privacy');
  } else {
    console.log('  ⚠ brak sekcji RODO — pomijam 14');
  }

  await browser.close();
  console.log(`\nŚcieżka klienta przeszła w całości: ${zrobione.length} zrzutów.`);
})().catch(async (e) => {
  console.error(`\nPrzerwane: ${e.message}`);
  process.exit(1);
});
