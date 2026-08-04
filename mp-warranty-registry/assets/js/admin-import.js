/**
 * Pętla importu CSV w adminie: batch po batchu przez AJAX (ten sam silnik
 * co WP-CLI). Każdy batch niesie token joba — po „Wznów" w innym oknie
 * stary token dostaje odmowę i ta pętla grzecznie staje.
 *
 * @package MP\Registry
 */

( function () {
	'use strict';

	var cfg = window.mpImportCfg;

	if ( ! cfg ) {
		return;
	}

	var statusBox = document.getElementById( 'mp-import-status' );
	var message = document.getElementById( 'mp-import-message' );
	var progress = document.getElementById( 'mp-import-progress' );
	var resumeBtn = document.getElementById( 'mp-import-resume' );
	var live = document.getElementById( 'mp-import-live' );
	var alertBox = document.getElementById( 'mp-import-alert' );
	var running = false;
	var lastAnnounced = -1;

	/**
	 * Ogłasza spokojnie (postęp, zakończenie) — nie przerywa czytnikowi.
	 *
	 * @param {string} text Tekst do ogłoszenia.
	 */
	function announce( text ) {
		if ( alertBox ) {
			alertBox.textContent = '';
		}

		if ( live ) {
			live.textContent = text;
		}
	}

	/**
	 * Ogłasza natychmiast (błąd) — przerywa, bo import stanął i czeka na człowieka.
	 *
	 * @param {string} text Tekst do ogłoszenia.
	 */
	function announceError( text ) {
		if ( live ) {
			live.textContent = '';
		}

		if ( alertBox ) {
			alertBox.textContent = text;
		}
	}

	/**
	 * Postęp ogłaszany co pełne 10%, a nie po każdej paczce. Import po 200 wierszy
	 * daje kilkadziesiąt aktualizacji na minutę — czytnik czytałby je bez przerwy
	 * i zagłuszył komunikat, na który operator naprawdę czeka.
	 *
	 * @param {number} processed Przetworzone wiersze.
	 * @param {number} total     Wszystkie wiersze.
	 */
	function announceProgress( processed, total ) {
		var percent = total > 0 ? Math.floor( ( processed * 100 ) / total ) : 0;
		var step = Math.floor( percent / 10 ) * 10;

		if ( step <= lastAnnounced ) {
			return;
		}

		lastAnnounced = step;
		announce( sprintf( cfg.i18n.srProgress, [ step ] ) );
	}

	function sprintf( template, args ) {
		return template.replace( /%(\d)\$s/g, function ( _match, index ) {
			return String( args[ Number( index ) - 1 ] );
		} );
	}

	function show( text, extra ) {
		if ( statusBox ) {
			statusBox.classList.remove( 'hidden' );
		}

		if ( message ) {
			message.textContent = extra ? text + ' ' + extra : text;
		}
	}

	function paint( processed, total, errors ) {
		if ( progress ) {
			progress.max = Math.max( 1, total );
			progress.value = processed;
		}

		show( sprintf( cfg.i18n.progress, [ processed, total, errors ] ) );
		announceProgress( processed, total );
	}

	function post( action, fields ) {
		var body = new FormData();

		body.append( 'action', action );
		body.append( 'nonce', cfg.nonce );

		Object.keys( fields ).forEach( function ( key ) {
			body.append( key, fields[ key ] );
		} );

		return fetch( cfg.ajaxUrl, { method: 'POST', credentials: 'same-origin', body: body } ).then(
			function ( response ) {
				return response.json();
			}
		);
	}

	function finish( data ) {
		running = false;

		if ( progress ) {
			progress.value = progress.max;
		}

		var text = sprintf( cfg.i18n.done, [ data.processed, data.total, data.errors ] );
		var extra = data.errors > 0 ? cfg.i18n.doneErrors : '';

		show( text, extra );

		// Zakonczenie ogłaszamy ZAWSZE, niezaleznie od progu 10% — to jest ten
		// jeden komunikat, na ktory operator czeka.
		lastAnnounced = 100;
		announce( extra ? text + ' ' + extra : text );
	}

	function fail( text ) {
		running = false;
		show( text );
		announceError( text );

		if ( resumeBtn ) {
			resumeBtn.classList.remove( 'hidden' );
		}
	}

	function loop( jobId, token ) {
		if ( running ) {
			return;
		}

		running = true;
		lastAnnounced = -1;
		announce( cfg.i18n.srStarted );

		if ( resumeBtn ) {
			resumeBtn.classList.add( 'hidden' );
		}

		( function next() {
			post( 'mp_import_batch', { job_id: jobId, token: token } )
				.then( function ( json ) {
					if ( ! json || ! json.success ) {
						fail( json && json.data && json.data.message ? json.data.message : cfg.i18n.netError );
						return;
					}

					paint( json.data.processed, json.data.total, json.data.errors );

					if ( 'processing' === json.data.status ) {
						next();
						return;
					}

					finish( json.data );
				} )
				.catch( function () {
					fail( cfg.i18n.netError );
				} );
		} )();
	}

	// ⚠️ TEST PILNUJĄCY WZNAWIANIA. Flaga `running` jest WSPÓLNA dla wszystkich zadań, więc przy
	// dwóch zawieszonych importach i szybkim kliknięciu obu przycisków serwer rezerwował OBA,
	// ale pętla ruszała tylko dla tego, którego odpowiedź wróciła pierwsza — drugi zostawał
	// zarezerwowany i nieodpytywany (osierocony import). Znalezione czytaniem liniowym 30.07.
	// Naprawa: jedno wznawianie na raz + blokada wszystkich przycisków na czas próby.
	var reclaiming = false;

	function przyciskiWznawiania() {
		var lista = [];

		if ( resumeBtn ) {
			lista.push( resumeBtn );
		}

		Array.prototype.forEach.call( document.querySelectorAll( '.mp-import-resume-stale' ), function ( b ) {
			lista.push( b );
		} );

		return lista;
	}

	function blokujPrzyciski( zablokowane ) {
		przyciskiWznawiania().forEach( function ( b ) {
			b.disabled = zablokowane;
		} );
	}

	function reclaim( jobId ) {
		if ( reclaiming || running ) {
			return;
		}

		reclaiming = true;
		blokujPrzyciski( true );
		show( cfg.i18n.resuming );

		post( 'mp_import_reclaim', { job_id: jobId } )
			.then( function ( json ) {
				reclaiming = false;

				if ( ! json || ! json.success ) {
					blokujPrzyciski( false );
					fail( json && json.data && json.data.message ? json.data.message : cfg.i18n.netError );
					return;
				}

				paint( json.data.processed, json.data.total, json.data.errors );
				loop( jobId, json.data.token );
			} )
			.catch( function () {
				reclaiming = false;
				blokujPrzyciski( false );
				fail( cfg.i18n.netError );
			} );
	}

	if ( resumeBtn ) {
		resumeBtn.addEventListener( 'click', function () {
			reclaim( Number( resumeBtn.getAttribute( 'data-job' ) ) );
		} );
	}

	Array.prototype.forEach.call( document.querySelectorAll( '.mp-import-resume-stale' ), function ( btn ) {
		btn.addEventListener( 'click', function () {
			reclaim( Number( btn.getAttribute( 'data-job' ) ) );
		} );
	} );

	if ( cfg.job && cfg.job.token && 'processing' === cfg.job.status ) {
		paint( cfg.job.processed, cfg.job.total, cfg.job.errors );
		loop( cfg.job.id, cfg.job.token );
	} else if ( cfg.job && 'processing' === cfg.job.status && resumeBtn ) {
		// Żywy job bez tokenu w tym oknie (np. odświeżona karta) — pokaż „Wznów".
		resumeBtn.classList.remove( 'hidden' );
	}
} )();
