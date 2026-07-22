/**
 * Formularz zgłoszenia MP — dynamiczne pola wg rodzaju (flaga #15).
 *
 * Progressive enhancement: formularz renderuje UNIĘ pól wszystkich rodzajów;
 * ten skrypt pokazuje pola właściwe dla wybranego rodzaju i toggluje atrybut
 * `required`. Bez JS formularz i tak działa — serwer waliduje fields_for(kind)
 * na submit (źródło prawdy). Config w window.mpIntakeForm (wp_localize_script).
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
	 * Ustawia widoczność i `required` pól dla danego rodzaju.
	 *
	 * @param {string} kind Wybrany rodzaj.
	 * @return {void}
	 */
	function apply( kind ) {
		var spec = cfg.kinds[ kind ] || [];
		var byKey = {};

		spec.forEach( function ( field ) {
			byKey[ field.key ] = field;
		} );

		cfg.allFields.forEach( function ( key ) {
			var wrap = wrapFor( key );

			if ( ! wrap ) {
				return;
			}

			var control = controlIn( wrap );
			var inKind = Object.prototype.hasOwnProperty.call( byKey, key );

			if ( inKind ) {
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
				// bez wysyłki (serwer i tak ignoruje pola spoza fields_for(kind),
				// ale disabled = czysty POST).
				if ( control ) {
					control.removeAttribute( 'required' );
					control.disabled = true;
				}
			}

			// Pole wracające do rodzaju musi znów wysyłać wartość.
			if ( inKind && control ) {
				control.disabled = false;
			}
		} );
	}

	apply( select.value );

	select.addEventListener( 'change', function () {
		apply( select.value );
	} );
}() );
