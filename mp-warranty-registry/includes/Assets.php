<?php
/**
 * Wersja plikow przegladarkowych (CSS/JS) — jedno miejsce dla calego rejestru.
 *
 * ⛔ Rejestr podpinal swoje pliki SAMA wersja wtyczki. Skutek: poprawka dotykajaca
 * wylacznie stylu albo skryptu, wydana bez podniesienia numeru wersji, NIE dociera
 * do przegladarek, ktore maja stary plik w pamieci podrecznej — uzytkownik widzi
 * stara wersje i nikt sie o tym nie dowiaduje.
 *
 * Rozwiazanie lezalo w sasiednim module: automator liczy `wersja . '.' . filemtime`
 * (`Admin/PanelScreen::asset_ver()`). To jest ten sam wzorzec, rozciagniety na rejestr.
 *
 * @package MP\Registry
 */

namespace MP\Registry;

/**
 * Znacznik wersji zasobow przegladarkowych.
 */
final class Assets {

	/**
	 * Wersja do parametru `ver` przy podpinaniu pliku.
	 *
	 * Brak pliku (albo `filemtime()` odmawia) => sama wersja wtyczki. Znacznik ma
	 * poprawiac odswiezanie, a nie wywracac ekran, gdy pliku chwilowo nie ma.
	 *
	 * @param string $rel_path Sciezka pliku wzgledem katalogu wtyczki.
	 * @return string
	 */
	public static function ver( string $rel_path ): string {
		$file  = plugin_dir_path( MP_REGISTRY_FILE ) . ltrim( $rel_path, '/' );
		$mtime = file_exists( $file ) ? (int) filemtime( $file ) : 0;

		return $mtime > 0 ? MP_REGISTRY_VERSION . '.' . $mtime : MP_REGISTRY_VERSION;
	}
}
