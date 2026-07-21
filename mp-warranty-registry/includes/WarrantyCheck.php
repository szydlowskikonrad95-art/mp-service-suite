<?php
/**
 * Filtr mp_warranty_check — publiczne API Registry (API-KONTRAKT.md).
 *
 * Przez hook przechodza WYLACZNIE skalary i tablice. Dokument zakupu NIE
 * wychodzi przez hook — porownanie $verify odbywa sie U NAS (minimalizacja PII).
 *
 * @package MP\Registry
 */

namespace MP\Registry;

/**
 * Budowa zwrotki mp_warranty_check.
 */
final class WarrantyCheck {

	/**
	 * Wersja ksztaltu zwrotki.
	 */
	public const SCHEMA_VERSION = 1;

	/**
	 * Handler filtra mp_warranty_check.
	 *
	 * @param mixed                     $result  Wartosc wejsciowa filtra (ignorowana — B jest zrodlem).
	 * @param string                    $serial  Surowy numer seryjny.
	 * @param int|null                  $case_id Sprawa pytajaca (dla wyjatkow per-sprawa).
	 * @param array<string,string>|null $verify  Opcjonalnie {purchase_doc, purchase_date}.
	 * @return array<string, mixed> Zwrotka wg API-KONTRAKT.md.
	 */
	public static function handle( $result, string $serial, ?int $case_id = null, ?array $verify = null ): array {
		$row = Repo::find_by_serial( $serial );

		return self::build( $row, $case_id, $verify );
	}

	/**
	 * Sklada zwrotke z wiersza rejestru (czysta funkcja poza odczytem wyjatku).
	 *
	 * @param array<string, mixed>|null $row     Wiersz rejestru lub null.
	 * @param int|null                  $case_id Sprawa pytajaca.
	 * @param array<string,string>|null $verify  Dane zakupu do porownania.
	 * @return array<string, mixed> Zwrotka.
	 */
	public static function build( ?array $row, ?int $case_id, ?array $verify ): array {
		$exception = null !== $row ? Repo::get_active_exception( (int) $row['id'], $case_id ) : null;

		return self::assemble( $row, $exception, $verify );
	}

	/**
	 * CZYSTE zlozenie zwrotki (bez dostepu do bazy — testowane jednostkowo).
	 *
	 * @param array<string, mixed>|null $row       Wiersz rejestru lub null.
	 * @param array<string, mixed>|null $exception Aktywny wyjatek lub null.
	 * @param array<string,string>|null $verify    Dane zakupu do porownania.
	 * @return array<string, mixed> Zwrotka.
	 */
	public static function assemble( ?array $row, ?array $exception, ?array $verify ): array {
		$found = null !== $row;

		$doc_match  = null;
		$date_match = null;

		if ( $found && null !== $verify ) {
			$doc_match  = self::compare( $row['purchase_document'] ?? '', $verify['purchase_doc'] ?? null );
			$date_match = self::compare( $row['purchase_date'] ?? '', $verify['purchase_date'] ?? null );
		}

		return array(
			'found'               => $found,
			'archived'            => $found && '1' === (string) ( $row['archived'] ?? '0' ),
			'purchase_doc_match'  => $doc_match,
			'purchase_date_match' => $date_match,
			'product_id'          => $found ? (int) $row['id'] : null,
			'serial_normalized'   => $found ? (string) $row['serial_normalized'] : null,
			'model'               => $found ? (string) $row['model'] : null,
			'batch'               => $found ? (string) $row['batch'] : null,
			'status'              => WarrantyStatus::compute(
				$found,
				$found ? ( $row['warranty_until'] ?? null ) : null,
				$doc_match,
				$date_match
			),
			'warranty_until'      => $found ? ( $row['warranty_until'] ?? null ) : null,
			'is_overridden'       => null !== $exception,
			'exception_id'        => null !== $exception ? (int) $exception['id'] : null,
			'override_until'      => null !== $exception ? ( $exception['valid_until'] ?? null ) : null,
			'override_reason'     => null !== $exception ? (string) $exception['reason'] : null,
			'checked_at'          => gmdate( 'Y-m-d\TH:i:s\Z' ),
			'registry_updated_at' => $found ? ( $row['updated_at'] ?? null ) : null,
			'schema_version'      => self::SCHEMA_VERSION,
		);
	}

	/**
	 * Porownanie wartosci weryfikowanej z rejestrem.
	 *
	 * @param string      $registry_value Wartosc w rejestrze.
	 * @param string|null $given          Wartosc od klienta (null = nie podano).
	 * @return bool|null true/false; null = brak danych do porownania.
	 */
	private static function compare( string $registry_value, ?string $given ): ?bool {
		if ( null === $given || '' === trim( $given ) || '' === trim( $registry_value ) ) {
			return null;
		}

		return strtolower( trim( $registry_value ) ) === strtolower( trim( $given ) );
	}
}
