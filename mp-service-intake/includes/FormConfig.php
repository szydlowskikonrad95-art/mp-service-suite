<?php
/**
 * Konfiguracja formularza — PLASKI schemat per RODZAJ sprawy (kontrakt C).
 *
 * ZERO logiki warunkowej pole-od-pola (ostrzezenie przed „wlasnym form-builderem"):
 * kazdy rodzaj to lista pol {key, label, type, required, pii_sensitive}.
 * Bez zapisanej konfiguracji dziala domyslna mapa z tej klasy.
 *
 * ⛔ EKRANU EDYCJI TYCH POL NIE MA — i nie jest to przeoczenie (audyt 2.56).
 * Naglowek obiecywal wczesniej, ze „admin edytuje wymagalnosc bez zmiany kodu",
 * przez co informatyk klienta szukal w panelu ekranu, ktorego nikt nie zbudowal:
 * opcja `mp_intake_form_config` byla tylko CZYTANA (`fields_for`), a zapisu nie
 * bylo nigdzie — ani ekranu, ani polecenia wiersza polecen.
 *
 * Zamawiajacy edytowania pol z panelu NIE zamawial (kartka wymaga „wymaganych pol
 * i zalacznikow zaleznych od kategorii produktu" — to robia `category_fields`
 * i `attachments_for`), wiec ekranu nie dokladamy. Nadpisanie zostaje jako furtka
 * dla WDROZENIOWCA: ustawia sie ja programowo albo z wiersza polecen, np.
 *   wp option update mp_intake_form_config '<json>' --format=json --autoload=no
 * ⚠️ `--autoload=no` jest istotne: konfiguracja czytana jest dopiero przy render
 * formularza, wiec nie ma po co wisiec w pamieci na kazdym zadaniu.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

/**
 * Definicje pol formularza per rodzaj zgloszenia.
 */
final class FormConfig {

	/**
	 * Opcja z nadpisana konfiguracja pol (warstwa TRESCI — kasowana przy
	 * odinstalowaniu ZA ZGODA admina, `uninstall.php`).
	 *
	 * Tylko do ODCZYTU z poziomu produktu: ustawia ja wdrozeniowiec (patrz
	 * naglowek klasy). Zaden ekran ani polecenie wtyczki jej nie zapisuje.
	 */
	public const OPTION = 'mp_intake_form_config';

	/**
	 * Dozwolone rodzaje spraw (zamknieta lista).
	 */
	public const KINDS = array( 'reklamacja', 'naprawa', 'zapytanie', 'zwrot' );

	/**
	 * Dozwolone typy pol (zamknieta lista — walidator zna kazdy).
	 */
	public const FIELD_TYPES = array( 'text', 'textarea', 'serial', 'document', 'date', 'email', 'tel' );

	/**
	 * Dozwolone kategorie produktu (spojne z Registry\Categories — slownik klepniety 21.07).
	 * Formularz P1.2: pola zaleza od WYBRANEJ kategorii (kartka). Pusta = brak kategorii (fallback).
	 */
	public const CATEGORY_SLUGS = array( 'audio', 'agd', 'elektronarzedzia', 'inne' );

	/**
	 * Domyslna mapa pol per rodzaj (uzywana gdy brak nadpisania w opcji).
	 *
	 * @return array<string, array<int, array{key: string, label: string, type: string, required: bool, pii_sensitive: bool}>>
	 */
	public static function defaults(): array {
		$serial   = array(
			'key'           => 'serial',
			'label'         => __( 'Numer seryjny produktu', 'mp-service-intake' ),
			'type'          => 'serial',
			'required'      => true,
			'pii_sensitive' => false,
		);
		$document = array(
			'key'           => 'purchase_document',
			'label'         => __( 'Dokument zakupu (nr faktury/paragonu)', 'mp-service-intake' ),
			'type'          => 'document',
			'required'      => true,
			'pii_sensitive' => true,
		);
		$date     = array(
			'key'           => 'purchase_date',
			'label'         => __( 'Data zakupu', 'mp-service-intake' ),
			'type'          => 'date',
			'required'      => true,
			'pii_sensitive' => false,
		);
		$issue    = array(
			'key'           => 'issue_description',
			'label'         => __( 'Opis usterki / sprawy', 'mp-service-intake' ),
			'type'          => 'textarea',
			'required'      => true,
			'pii_sensitive' => true,
		);

		return array(
			'reklamacja' => array( $serial, $document, $date, $issue ),
			'naprawa'    => array( $serial, $issue ),
			'zapytanie'  => array( $issue ),
			'zwrot'      => array(
				$serial,
				$document,
				$date,
				array(
					'key'           => 'return_reason',
					'label'         => __( 'Powód zwrotu', 'mp-service-intake' ),
					'type'          => 'textarea',
					'required'      => true,
					// RODO: to jest SWOBODNY OPIS pisany przez klienta — bliznniacze pole
					// `issue_description` ma te flage od poczatku. Bez niej redakcja
					// (CaseRepo::redact_pii_fields) omijala to pole i tresc zostawala
					// w bazie PO wykonanym zadaniu usuniecia danych.
					'pii_sensitive' => true,
				),
			),
		);
	}

	/**
	 * Klucze pol, ktore sa WRAZLIWE wg AKTUALNEJ konfiguracji — po wszystkich
	 * rodzajach spraw i wszystkich kategoriach.
	 *
	 * ⛔ PO CO TO ISTNIEJE: flaga `pii_sensitive` jest ZAPISYWANA W WIERSZU SPRAWY
	 * w chwili zlozenia zgloszenia. Samo poprawienie flagi w tej klasie naprawia
	 * wiec wylacznie sprawy PRZYSZLE — sprawy juz lezace w bazie maja w sobie stara
	 * wartosc i przy zadaniu usuniecia danych dalej byly by pomijane. Ta sama
	 * pulapka co przy kontach zalozonych przed poprawka tozsamosci klienta:
	 * poprawka, ktora nie obejmuje tego, co juz jest, chroni tylko nowych.
	 *
	 * Redakcja pyta wiec RAZ o aktualna liste kluczy i traktuje ja jako obowiazujaca
	 * — bez migracji przepisujacej stare wiersze.
	 *
	 * @return array<int, string> Klucze pol wrazliwych (bez powtorzen).
	 */
	public static function sensitive_keys(): array {
		$klucze = array();

		foreach ( self::KINDS as $kind ) {
			foreach ( self::fields_for( $kind ) as $field ) {
				if ( ! empty( $field['pii_sensitive'] ) ) {
					$klucze[ (string) $field['key'] ] = true;
				}
			}
		}

		foreach ( self::CATEGORY_SLUGS as $slug ) {
			foreach ( self::category_fields( $slug ) as $field ) {
				if ( ! empty( $field['pii_sensitive'] ) ) {
					$klucze[ (string) $field['key'] ] = true;
				}
			}
		}

		return array_keys( $klucze );
	}

	/**
	 * Zwraca liste pol dla rodzaju (z nadpisania w opcji albo domyslna), plus
	 * dodatkowe pola kategorii gdy $category niepuste (P1.2).
	 *
	 * @param string $kind     Rodzaj sprawy.
	 * @param string $category Slug kategorii (pusty = tylko pola rodzaju).
	 * @return array<int, array{key: string, label: string, type: string, required: bool, pii_sensitive: bool}>
	 */
	public static function fields_for( string $kind, string $category = '' ): array {
		$config = get_option( self::OPTION, array() );

		if ( is_array( $config ) && isset( $config[ $kind ] ) && is_array( $config[ $kind ] ) ) {
			$base = self::sanitize_kind_fields( $config[ $kind ] );
		} else {
			$defaults = self::defaults();
			$base     = $defaults[ $kind ] ?? array();
		}

		if ( '' === $category ) {
			return $base;
		}

		// Pola kategorii dopisane PO polach rodzaju (dedup po kluczu — rodzaj wygrywa).
		$seen = array();
		foreach ( $base as $field ) {
			$seen[ $field['key'] ] = true;
		}

		foreach ( self::category_fields( $category ) as $field ) {
			if ( ! isset( $seen[ $field['key'] ] ) ) {
				$seen[ $field['key'] ] = true;
				$base[]                = $field;
			}
		}

		return $base;
	}

	/**
	 * Etykiety rodzajow sprawy — JEDNO zrodlo dla calego zestawu.
	 *
	 * Ten sam rodzaj nazywal sie w produkcie na TRZY sposoby: „Zapytanie" na
	 * formularzu, „Zapytanie techniczne" w panelu automatu i surowy klucz
	 * `zapytanie` na liscie spraw personelu. Klient, koordynator i pracownik
	 * mowili o jednej sprawie trzema slowami — przy rozmowie telefonicznej to
	 * realne nieporozumienie. Brzmienie bierzemy z zamowienia („zapytanie
	 * techniczne"), a inne moduly czytaja te mape zaczepem `mp_case_kind_labels`,
	 * zeby nie zalezec od tej wtyczki twardo.
	 *
	 * @return array<string, string>
	 */
	public static function kind_labels(): array {
		$filtered = apply_filters( 'mp_case_kind_labels', self::default_kind_labels() );

		return ( is_array( $filtered ) && array() !== $filtered ) ? $filtered : self::default_kind_labels();
	}

	/**
	 * Domyslne etykiety rodzajow (bez filtra — zrodlo, nie wynik).
	 *
	 * @return array<string, string>
	 */
	public static function default_kind_labels(): array {
		return array(
			'reklamacja' => __( 'Reklamacja', 'mp-service-intake' ),
			'naprawa'    => __( 'Naprawa', 'mp-service-intake' ),
			'zapytanie'  => __( 'Zapytanie techniczne', 'mp-service-intake' ),
			'zwrot'      => __( 'Zwrot', 'mp-service-intake' ),
		);
	}

	/**
	 * Odpowiedz na zaczep `mp_case_kind_labels` — zeby INNE moduly pytaly o nazwy
	 * rodzajow zamiast trzymac wlasne kopie (stad brala sie rozbieznosc nazw).
	 * Gdy ktos przekazal juz niepusta mape, zostawiamy jego.
	 *
	 * @param mixed $labels Mapa przekazana przez pytajacego.
	 * @return array<string, string>
	 */
	public static function provide_kind_labels( $labels ): array {
		return ( is_array( $labels ) && array() !== $labels ) ? $labels : self::default_kind_labels();
	}

	/**
	 * Etykieta jednego rodzaju (nieznany => surowy klucz, zeby nic nie zniknelo).
	 *
	 * @param string $kind Klucz rodzaju.
	 * @return string
	 */
	public static function kind_label( string $kind ): string {
		$labels = self::kind_labels();

		return isset( $labels[ $kind ] ) ? (string) $labels[ $kind ] : $kind;
	}

	/**
	 * Czy rodzaj jest dozwolony.
	 *
	 * @param string $kind Rodzaj.
	 * @return bool
	 */
	public static function is_valid_kind( string $kind ): bool {
		return in_array( $kind, self::KINDS, true );
	}

	/**
	 * Mapa rodzaj => lista {key, required} dla WSZYSTKICH rodzajow.
	 *
	 * Config dla warstwy klienckiej (JS): mowi ktore pola nalezą do rodzaju i
	 * ktore sa wymagane. JS pokazuje/ukrywa pola i toggluje `required` wg tej
	 * mapy; serwer NIEZALEZNIE waliduje fields_for(kind) na submit (JS = tylko UX).
	 *
	 * @return array<string, array<int, array{key: string, required: bool}>>
	 */
	public static function kind_field_map(): array {
		$map = array();

		foreach ( self::KINDS as $kind ) {
			$fields = array();

			foreach ( self::fields_for( $kind ) as $field ) {
				$fields[] = array(
					'key'      => $field['key'],
					'required' => $field['required'],
				);
			}

			$map[ $kind ] = $fields;
		}

		return $map;
	}

	/**
	 * Unia definicji pol po WSZYSTKICH rodzajach (dedup po kluczu — pierwsza
	 * definicja wygrywa). Formularz renderuje KAZDE mozliwe pole raz; JS
	 * pokazuje wlasciwe dla wybranego rodzaju. Dzieki temu np. `return_reason`
	 * (tylko zwrot) istnieje w DOM od poczatku — brak dwuetapowego "wyslij->blad".
	 *
	 * @return array<int, array{key: string, label: string, type: string, required: bool, pii_sensitive: bool}>
	 */
	public static function union_fields(): array {
		$seen = array();
		$out  = array();

		foreach ( self::KINDS as $kind ) {
			foreach ( self::fields_for( $kind ) as $field ) {
				if ( isset( $seen[ $field['key'] ] ) ) {
					continue;
				}

				$seen[ $field['key'] ] = true;
				$out[]                 = $field;
			}
		}

		foreach ( self::CATEGORY_SLUGS as $category ) {
			foreach ( self::category_fields( $category ) as $field ) {
				if ( isset( $seen[ $field['key'] ] ) ) {
					continue;
				}

				$seen[ $field['key'] ] = true;
				$out[]                 = $field;
			}
		}

		return $out;
	}

	/**
	 * Kategorie produktu (slug => etykieta PL). Spojne z Registry\Categories.
	 * Konfigurowalne filtrem `mp_intake_categories`.
	 *
	 * @return array<string, string>
	 */
	public static function categories(): array {
		$map = array(
			'audio'            => __( 'Elektronika audio', 'mp-service-intake' ),
			'agd'              => __( 'AGD drobne', 'mp-service-intake' ),
			'elektronarzedzia' => __( 'Elektronarzędzia', 'mp-service-intake' ),
			'inne'             => __( 'Inne', 'mp-service-intake' ),
		);

		$filtered = apply_filters( 'mp_intake_categories', $map );

		return ( is_array( $filtered ) && array() !== $filtered ) ? $filtered : $map;
	}

	/**
	 * Czy kategoria dozwolona (pusta = brak wyboru, dozwolona jako fallback).
	 *
	 * @param string $category Slug kategorii.
	 * @return bool
	 */
	public static function is_valid_category( string $category ): bool {
		return '' === $category || in_array( $category, self::CATEGORY_SLUGS, true );
	}

	/**
	 * Domyslne dodatkowe pola per kategoria (P1.2 — sensowne domyslne, konfigurowalne).
	 * PLASKI schemat jak pola rodzaju, ZERO logiki warunkowej.
	 *
	 * @return array<string, array<int, array<string, mixed>>>
	 */
	private static function category_fields_defaults(): array {
		return array(
			'audio'            => array(
				array(
					'key'           => 'cat_audio_objaw',
					'label'         => __( 'Objaw dźwięku (np. brak dźwięku, trzaski, jeden kanał)', 'mp-service-intake' ),
					'type'          => 'text',
					'required'      => false,
					// RODO: pole SWOBODNEGO OPISU sytuacji, ta sama klasa co opis usterki
					// — czlowiek wpisuje tam, co uwaza, i nierzadko wlasne okolicznosci.
					// Pozostale pola kategorii (model z tabliczki, nr partii) zostaja bez
					// flagi SWIADOMIE: identyfikuja EGZEMPLARZ, nie osobe, a ich redakcja
					// odebralaby serwisowi dane techniczne sprzetu.
					'pii_sensitive' => true,
				),
			),
			'agd'              => array(
				array(
					'key'           => 'cat_agd_model',
					'label'         => __( 'Model / moc z tabliczki znamionowej', 'mp-service-intake' ),
					'type'          => 'text',
					'required'      => false,
					'pii_sensitive' => false,
				),
			),
			'elektronarzedzia' => array(
				array(
					'key'           => 'cat_et_partia',
					'label'         => __( 'Nr partii / seria produktu', 'mp-service-intake' ),
					'type'          => 'text',
					'required'      => false,
					'pii_sensitive' => false,
				),
			),
			'inne'             => array(),
		);
	}

	/**
	 * Dodatkowe pola dla kategorii (z filtra konfiguracyjnego + sanityzacja).
	 *
	 * @param string $category Slug kategorii.
	 * @return array<int, array{key: string, label: string, type: string, required: bool, pii_sensitive: bool}>
	 */
	public static function category_fields( string $category ): array {
		if ( '' === $category ) {
			return array();
		}

		$map = apply_filters( 'mp_intake_category_fields', self::category_fields_defaults() );

		$fields = ( is_array( $map ) && isset( $map[ $category ] ) && is_array( $map[ $category ] ) )
			? $map[ $category ]
			: array();

		return self::sanitize_kind_fields( $fields );
	}

	/**
	 * Domyslne reguly ZALACZNIKOW per kategoria (druga polowa P1.2).
	 *
	 * Kartka, Plugin 1: „wymagane pola I ZALACZNIKI zalezne od wybranej
	 * kategorii produktu". Pola robil `category_fields()` od poczatku,
	 * zalaczniki NIE — we wszystkich kategoriach byly identyczne i zawsze
	 * opcjonalne (wlasny GAP-TRACKER trzymal P1.2 na 🔨, nie ✅).
	 *
	 * Regula klepnieta 28.07: sprzet z tabliczka znamionowa (AGD,
	 * elektronarzedzia) wymaga zdjecia — bez niego serwis nie ustali modelu
	 * ani mocy. Audio i „inne" zostaja opcjonalne (zero regresji).
	 *
	 * PLASKI schemat jak pola: kategoria => {required, label}. Zero logiki
	 * warunkowej, konfigurowalne filtrem bez zmiany kodu.
	 *
	 * @return array<string, array{required: bool, label: string}>
	 */
	private static function category_attachments_defaults(): array {
		return array(
			'audio'            => array(
				'required' => false,
				'label'    => self::attachment_label_optional(),
			),
			'agd'              => array(
				'required' => true,
				'label'    => __( 'Zdjęcie tabliczki znamionowej — wymagane (zdjęcie lub PDF, do 5 plików)', 'mp-service-intake' ),
			),
			'elektronarzedzia' => array(
				'required' => true,
				'label'    => __( 'Zdjęcie tabliczki znamionowej lub numeru partii — wymagane (zdjęcie lub PDF, do 5 plików)', 'mp-service-intake' ),
			),
			'inne'             => array(
				'required' => false,
				'label'    => self::attachment_label_optional(),
			),
		);
	}

	/**
	 * Reguly zalacznika dla kategorii (z filtra konfiguracyjnego + sanityzacja).
	 *
	 * ⚠️ Fallback MIEKKI z rozmyslem: pusta kategoria (klient jej nie wybral —
	 * pole jest opcjonalne) i kategoria spoza slownika NIE wymagaja zalacznika.
	 * Twardy fallback zablokowalby kazde zgloszenie bez wyboru kategorii.
	 *
	 * @param string $category Slug kategorii (pusty = brak wyboru).
	 * @return array{required: bool, label: string}
	 */
	public static function attachments_for( string $category ): array {
		$defaults = self::category_attachments_defaults();
		$map      = apply_filters( 'mp_intake_category_attachments', $defaults );

		if ( ! is_array( $map ) ) {
			$map = $defaults;
		}

		$rules = ( '' !== $category && isset( $map[ $category ] ) && is_array( $map[ $category ] ) )
			? $map[ $category ]
			: array();

		return self::sanitize_attachment_rules( $rules );
	}

	/**
	 * Sanityzacja regul zalacznika (wartosci moga przyjsc z filtra).
	 *
	 * @param array<string, mixed> $rules Surowe reguly.
	 * @return array{required: bool, label: string}
	 */
	private static function sanitize_attachment_rules( array $rules ): array {
		$required = ! empty( $rules['required'] );
		$label    = isset( $rules['label'] ) ? trim( (string) $rules['label'] ) : '';

		if ( '' === $label ) {
			$label = $required ? self::attachment_label_required() : self::attachment_label_optional();
		}

		return array(
			'required' => $required,
			'label'    => $label,
		);
	}

	/**
	 * Etykieta pola zalacznikow gdy nic nie jest wymagane (tresc sprzed P1.2 —
	 * kategorie bez wymogu wygladaja dokladnie jak przed zmiana).
	 *
	 * @return string
	 */
	private static function attachment_label_optional(): string {
		return __( 'Załączniki (opcjonalnie: zdjęcia, PDF — do 5 plików)', 'mp-service-intake' );
	}

	/**
	 * Etykieta zapasowa gdy filtr wymusil `required` bez podania etykiety —
	 * klient i tak musi zobaczyc, ze zalacznik jest obowiazkowy.
	 *
	 * @return string
	 */
	private static function attachment_label_required(): string {
		return __( 'Załącznik wymagany dla tej kategorii (zdjęcie lub PDF, do 5 plików)', 'mp-service-intake' );
	}

	/**
	 * Mapa kategoria => {required, label} dla warstwy klienckiej (JS).
	 * JS przelacza etykiete i gwiazdke przy zmianie kategorii; serwer waliduje
	 * NIEZALEZNIE w SubmissionHandler (JS = tylko UX).
	 *
	 * @return array<string, array{required: bool, label: string}>
	 */
	public static function category_attachment_map(): array {
		$map = array();

		foreach ( self::CATEGORY_SLUGS as $category ) {
			$map[ $category ] = self::attachments_for( $category );
		}

		return $map;
	}

	/**
	 * Mapa kategoria => lista {key, required} dla warstwy klienckiej (JS).
	 *
	 * @return array<string, array<int, array{key: string, required: bool}>>
	 */
	public static function category_field_map(): array {
		$map = array();

		foreach ( self::CATEGORY_SLUGS as $category ) {
			$fields = array();

			foreach ( self::category_fields( $category ) as $field ) {
				$fields[] = array(
					'key'      => $field['key'],
					'required' => $field['required'],
				);
			}

			$map[ $category ] = $fields;
		}

		return $map;
	}

	/**
	 * Czysci wiersz pol z opcji (obrona przed smieciem/zmiana schematu).
	 *
	 * @param array<int, mixed> $fields Surowe pola z opcji.
	 * @return array<int, array{key: string, label: string, type: string, required: bool, pii_sensitive: bool}>
	 */
	private static function sanitize_kind_fields( array $fields ): array {
		$out = array();

		foreach ( $fields as $field ) {
			if ( ! is_array( $field ) || '' === (string) ( $field['key'] ?? '' ) ) {
				continue;
			}

			$type = (string) ( $field['type'] ?? 'text' );

			$typ_pola = in_array( $type, self::FIELD_TYPES, true ) ? $type : 'text';

			// ⛔ BEZPIECZNA STRONA DOMYSLNA dla pol dokladanych przez administratora.
			// Dotad brak flagi znaczyl „nie wrazliwe", wiec KAZDE nowe pole swobodnego
			// tekstu bylo domyslnie POMIJANE przy usuwaniu danych — ta sama wada, ktora
			// wlasnie naprawiamy przy „Powodzie zwrotu", tyle ze na przyszlosc i bez
			// konca. Teraz: pole tekstowe bez jawnej decyzji jest traktowane jako
			// wrazliwe. Jawne `false` w konfiguracji dalej wygrywa — decyzja czlowieka
			// zostaje decyzja czlowieka, brak decyzji przestaje byc cichym „nie".
			$wrazliwe = array_key_exists( 'pii_sensitive', $field )
				? ! empty( $field['pii_sensitive'] )
				: in_array( $typ_pola, array( 'text', 'textarea' ), true );

			$out[] = array(
				'key'           => (string) $field['key'],
				'label'         => (string) ( $field['label'] ?? $field['key'] ),
				'type'          => $typ_pola,
				'required'      => ! empty( $field['required'] ),
				'pii_sensitive' => $wrazliwe,
			);
		}

		return $out;
	}
}
