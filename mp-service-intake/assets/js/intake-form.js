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
	 * Przelicza formularz wg aktualnych wyborów rodzaju i kategorii.
	 *
	 * @return {void}
	 */
	function refresh() {
		apply( select.value, catSelect ? catSelect.value : '' );
	}

	refresh();

	select.addEventListener( 'change', refresh );

	if ( catSelect ) {
		catSelect.addEventListener( 'change', refresh );
	}
}() );
