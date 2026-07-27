/**
 * Formularz zgłoszenia MP — dynamiczne pola wg rodzaju ORAZ kategorii (#15, P1.2).
 *
 * Progressive enhancement: formularz renderuje UNIĘ pól wszystkich rodzajów i
 * kategorii; ten skrypt pokazuje pola właściwe dla wybranego rodzaju + kategorii
 * i toggluje atrybut `required`. Bez JS formularz i tak działa — serwer waliduje
 * fields_for(kind, category) na submit (źródło prawdy). Config w window.mpIntakeForm.
 */
( function () {
	'use strict';

	var cfg = window.mpIntakeForm;

	if ( ! cfg || ! cfg.kinds || ! cfg.allFields ) {
		return;
	}

	var form = document.querySelector( 'form.mp-intake-form' );

	if ( ! form ) {
		return;
	}

	var select = form.querySelector( '#mp-f-kind' );

	if ( ! select ) {
		return;
	}

	var catSelect = form.querySelector( '#mp-f-category' );

	/**
	 * Opakowanie pola (<p data-mp-field="KEY">) w tym formularzu.
	 *
	 * @param {string} key Klucz pola.
	 * @return {Element|null}
	 */
	function wrapFor( key ) {
		return form.querySelector( '.mp-intake-field[data-mp-field="' + key + '"]' );
	}

	/**
	 * Kontrolka (input/textarea/select) wewnątrz opakowania.
	 *
	 * @param {Element} wrap Opakowanie pola.
	 * @return {Element|null}
	 */
	function controlIn( wrap ) {
		return wrap ? wrap.querySelector( 'input, textarea, select' ) : null;
	}

	/**
	 * Ustawia widoczność i `required` pól dla rodzaju + kategorii.
	 * Widoczne = pola rodzaju ∪ pola kategorii (rodzaj wygrywa przy kolizji klucza).
	 *
	 * @param {string} kind     Wybrany rodzaj.
	 * @param {string} category Wybrana kategoria (może być pusta).
	 * @return {void}
	 */
	function apply( kind, category ) {
		var spec = cfg.kinds[ kind ] || [];
		var catSpec = ( cfg.categories && cfg.categories[ category ] ) || [];
		var byKey = {};

		spec.forEach( function ( field ) {
			byKey[ field.key ] = field;
		} );

		catSpec.forEach( function ( field ) {
			if ( ! Object.prototype.hasOwnProperty.call( byKey, field.key ) ) {
				byKey[ field.key ] = field;
			}
		} );

		cfg.allFields.forEach( function ( key ) {
			var wrap = wrapFor( key );

			if ( ! wrap ) {
				return;
			}

			var control = controlIn( wrap );
			var inForm = Object.prototype.hasOwnProperty.call( byKey, key );

			if ( inForm ) {
				wrap.hidden = false;
				wrap.style.display = '';

				if ( control ) {
					if ( byKey[ key ].required ) {
						control.setAttribute( 'required', 'required' );
					} else {
						control.removeAttribute( 'required' );
					}
				}
			} else {
				wrap.hidden = true;
				wrap.style.display = 'none';

				// Ukryte pole nie może blokować ani nieść śmieci: bez `required`,
				// disabled = czysty POST (serwer i tak ignoruje pola spoza fields_for).
				if ( control ) {
					control.removeAttribute( 'required' );
					control.disabled = true;
				}
			}

			// Pole wracające do formularza musi znów wysyłać wartość.
			if ( inForm && control ) {
				control.disabled = false;
			}
		} );
	}

	/**
	 * Obszar, ktorym mowimy czytnikowi ekranu, ze formularz sie zmienil.
	 *
	 * Bez tego pola dochodza i znikaja BEZ SLOWA: osoba niewidoma wybiera rodzaj
	 * sprawy, formularz cicho dokłada „numer seryjny" i „dokument zakupu", a ona
	 * dowiaduje sie o nich dopiero przy probie wyslania. axe tego nie wykryje —
	 * to zachowanie w czasie, nie blad w statycznym HTML.
	 *
	 * @return {HTMLElement} Element komunikatow (tworzony raz, potem zwracany).
	 */
	function announcer() {
		var el = document.getElementById( 'mp-intake-announcer' );

		if ( ! el ) {
			el = document.createElement( 'p' );
			el.id = 'mp-intake-announcer';
			el.className = 'mp-intake-sr-only';
			el.setAttribute( 'role', 'status' );
			el.setAttribute( 'aria-live', 'polite' );
			form.insertBefore( el, form.firstChild );
		}

		return el;
	}

	/**
	 * Ogłasza, ktore pola sa teraz w formularzu (tylko po ZMIANIE, nie przy starcie).
	 *
	 * @param {Array<string>} etykiety Widoczne etykiety pol.
	 * @return {void}
	 */
	function ogloszenie( etykiety ) {
		var el = announcer();
		var tresc = etykiety.length
			? 'Formularz dopasowany. Pola do wypełnienia: ' + etykiety.join( ', ' ) + '.'
			: 'Formularz dopasowany.';

		// Ta sama tresc nie zostalaby ogloszona ponownie — czyscimy przed wpisem.
		el.textContent = '';
		window.setTimeout( function () {
			el.textContent = tresc;
		}, 60 );
	}

	/**
	 * Etykiety pol widocznych w tej chwili.
	 *
	 * @return {Array<string>} Lista etykiet.
	 */
	function widoczneEtykiety() {
		var lista = [];

		cfg.allFields.forEach( function ( key ) {
			var wrap = wrapFor( key );
			var label;

			if ( ! wrap || wrap.hidden ) {
				return;
			}

			label = wrap.querySelector( 'label' );

			if ( label ) {
				lista.push( label.textContent.trim().replace( /\s*\*$/, '' ) );
			}
		} );

		return lista;
	}

	/**
	 * Przelicza formularz wg aktualnych wyborow rodzaju i kategorii.
	 *
	 * @param {boolean} oglaszaj Czy powiedziec czytnikowi ekranu, co sie zmienilo
	 *                           (przy pierwszym przeliczeniu NIE — nic sie jeszcze nie zmienilo).
	 * @return {void}
	 */
	function refresh( oglaszaj ) {
		apply( select.value, catSelect ? catSelect.value : '' );

		if ( oglaszaj ) {
			ogloszenie( widoczneEtykiety() );
		}
	}

	refresh( false );

	select.addEventListener( 'change', function () {
		refresh( true );
	} );

	if ( catSelect ) {
		catSelect.addEventListener( 'change', function () {
			refresh( true );
		} );
	}

	// Po wyslaniu formularza strona wraca z komunikatem. Tresc obecna JUZ przy
	// wczytaniu nie jest ogłaszana przez czytnik (obszary live mowia o ZMIANACH),
	// wiec przenosimy na nia fokus — inaczej osoba niewidoma nie wie, czy zgloszenie
	// przeszlo, i szuka po omacku.
	window.setTimeout( function () {
		var komunikat = document.querySelector( '.mp-intake-error-summary, .mp-intake-notice' );

		if ( komunikat ) {
			komunikat.setAttribute( 'tabindex', '-1' );
			komunikat.focus();
		}
	}, 120 );
}() );
