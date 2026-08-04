<?php
/**
 * Wersja plikow przegladarkowych (CSS/JS) — jedno miejsce dla calego modulu zgloszen.
 *
 * ⛔ CZWARTE I OSTATNIE MIEJSCE pozycji 2.41. Modul zgloszen podpinal swoje
 * pliki SAMA wersja wtyczki — tak samo jak wczesniej rejestr. Skutek: poprawka dotykajaca
 * wylacznie stylu albo skryptu, wydana bez podniesienia numeru wersji, NIE dociera
 * do przegladarek, ktore maja stary plik w pamieci podrecznej — uzytkownik widzi
 * stara wersje i nikt sie o tym nie dowiaduje.
 *
 * Rozwiazanie lezalo w sasiednim module: automator liczy `wersja . '.' . filemtime`
 * (`Admin/PanelScreen::asset_ver()`). To jest ten sam wzorzec, rozciagniety najpierw na rejestr, a teraz na modul zgloszen.
 *
 * @package MP\Intake
 */

namespace MP\Intake;

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
		$file  = plugin_dir_path( MP_INTAKE_FILE ) . ltrim( $rel_path, '/' );
		$mtime = file_exists( $file ) ? (int) filemtime( $file ) : 0;

		return $mtime > 0 ? MP_INTAKE_VERSION . '.' . $mtime : MP_INTAKE_VERSION;
	}
}
