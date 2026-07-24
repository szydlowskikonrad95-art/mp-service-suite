/**
 * MP Automator — builder checklist/szablonow (P3.5, poprawka #2: JSON -> formularz).
 *
 * Kontrakt backendu bez zmian: przy submicie serializuje wiersze formularza do
 * ukrytego pola `payload` (JSON) — ten sam handler + walidacja co przy surowym JSON.
 * Bez JS: pole `payload` zostaje z prefillem (biezaca konfiguracja) => zapis = no-op
 * (zero utraty danych), a edycja mozliwa przez sekcje "Zaawansowane: edytuj jako JSON".
 */
( function () {
	'use strict';

	function rowsFor( fieldset, hasBody ) {
		var out = [];
		var rows = fieldset.querySelectorAll( '.mp-cfg-row' );
		for ( var i = 0; i < rows.length; i++ ) {
			var keyEl = rows[ i ].querySelector( '.mp-cfg-key' );
			var labelEl = rows[ i ].querySelector( '.mp-cfg-label' );
			var key = keyEl ? String( keyEl.value ).trim() : '';
			if ( '' === key ) {
				continue; // wiersz bez klucza pomijany (nie brudzi konfiguracji)
			}
			var item = { key: key, label: labelEl ? String( labelEl.value ) : '' };
			if ( hasBody ) {
				var bodyEl = rows[ i ].querySelector( '.mp-cfg-body' );
				item.body = bodyEl ? String( bodyEl.value ) : '';
			}
			out.push( item );
		}
		return out;
	}

	function serialize( form ) {
		var hasBody = '1' === form.getAttribute( 'data-has-body' );
		var data = {};
		var kinds = form.querySelectorAll( '.mp-cfg-kind' );
		for ( var i = 0; i < kinds.length; i++ ) {
			data[ kinds[ i ].getAttribute( 'data-kind' ) ] = rowsFor( kinds[ i ], hasBody );
		}
		return data;
	}

	function mkInput( cls, placeholder, label ) {
		var el = document.createElement( 'input' );
		el.type = 'text';
		el.className = cls;
		el.placeholder = placeholder;
		el.setAttribute( 'aria-label', label );
		return el;
	}

	function newRow( hasBody ) {
		// Bez innerHTML — czysty DOM (zero powierzchni na XSS; wartosci wpisuje user przez .value).
		var row = document.createElement( 'div' );
		row.className = 'mp-cfg-row';
		row.appendChild( mkInput( 'mp-cfg-key regular-text', 'klucz', 'Klucz' ) );
		row.appendChild( mkInput( 'mp-cfg-label regular-text', 'etykieta', 'Etykieta' ) );
		if ( hasBody ) {
			var ta = document.createElement( 'textarea' );
			ta.className = 'mp-cfg-body large-text';
			ta.rows = 2;
			ta.placeholder = 'treść (markery {{...}})';
			ta.setAttribute( 'aria-label', 'Treść szablonu' );
			row.appendChild( ta );
		}
		var btn = document.createElement( 'button' );
		btn.type = 'button';
		btn.className = 'button-link mp-cfg-remove';
		btn.setAttribute( 'aria-label', 'Usuń wiersz' );
		btn.textContent = '×';
		row.appendChild( btn );
		return row;
	}

	document.addEventListener( 'click', function ( e ) {
		var add = e.target.closest ? e.target.closest( '.mp-cfg-add' ) : null;
		if ( add ) {
			var form = add.closest( '.mp-config-builder' );
			var fs = add.closest( '.mp-cfg-kind' );
			if ( form && fs ) {
				fs.querySelector( '.mp-cfg-rows' ).appendChild( newRow( '1' === form.getAttribute( 'data-has-body' ) ) );
			}
			return;
		}
		var rm = e.target.closest ? e.target.closest( '.mp-cfg-remove' ) : null;
		if ( rm ) {
			var r = rm.closest( '.mp-cfg-row' );
			if ( r ) {
				r.remove();
			}
		}
	} );

	var forms = document.querySelectorAll( 'form.mp-config-builder' );
	for ( var i = 0; i < forms.length; i++ ) {
		( function ( form ) {
			form.addEventListener( 'submit', function () {
				var json = form.querySelector( '.mp-cfg-json' );
				if ( json ) {
					json.value = JSON.stringify( serialize( form ), null, 2 );
				}
			} );
		} )( forms[ i ] );
	}
} )();
