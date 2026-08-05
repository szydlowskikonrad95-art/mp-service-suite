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

	function paint( processed, total, errors, success ) {
		if ( progress ) {
			progress.max = Math.max( 1, total );
			progress.value = processed;
		}

		// Postep I wynik w jednym zdaniu — patrz komentarz przy „done" w ImportScreen.php.
		show( sprintf( cfg.i18n.progress, [ processed, total, success, errors ] ) );
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

	// Z1b (polowanie 2026-08-05): URL raportu bledow per job — z konfiguracji
	// (upload) albo ze zwrotki wznowienia. Musi powstac w PHP (nonce).
	var reportUrls = {};

	/**
	 * Z1b: baner mowil „Import zakończony: 8 z 8", a tabela „Ostatnie importy"
	 * tuz pod nim dalej „w trakcie, 0/8" az do recznego F5 — dwa elementy
	 * jednego ekranu przeczyly sobie. Po done odswiezamy wiersz tego importu.
	 *
	 * @param {number} jobId Job, ktory wlasnie sie zakonczyl.
	 * @param {Object} data  Zwrotka batcha (processed/total/errors).
	 */
	/**
	 * Ile wierszy PRZYJAL REJESTR. Serwer podaje to wprost (`success`); starsza
	 * zwrotka bez tego pola dopelniana jest arytmetycznie — kazdy przetworzony
	 * wiersz konczy albo sukcesem, albo bledem, wiec roznica jest dokladna.
	 *
	 * @param {Object} data Zwrotka batcha.
	 * @return {number} Liczba zaimportowanych wierszy.
	 */
	function zaimportowane( data ) {
		return typeof data.success === 'number' ? data.success : ( data.processed - data.errors );
	}

	function updateHistoryRow( jobId, data ) {
		var row = document.querySelector( '.mp-import-history tr[data-job="' + jobId + '"]' );

		if ( ! row ) {
			return;
		}

		var status = row.querySelector( '.mp-import-h-status' );
		var counts = row.querySelector( '.mp-import-h-counts' );
		var errors = row.querySelector( '.mp-import-h-errors' );
		var report = row.querySelector( '.mp-import-h-report' );

		if ( status ) {
			status.textContent = cfg.i18n.statusDone;
		}

		if ( counts ) {
			counts.textContent = zaimportowane( data ) + ' / ' + data.total;
		}

		if ( errors ) {
			errors.textContent = String( data.errors );
		}

		if ( report && data.errors > 0 && reportUrls[ jobId ] ) {
			var link = document.createElement( 'a' );
			link.href = reportUrls[ jobId ];
			link.textContent = cfg.i18n.reportLink;
			report.textContent = '';
			report.appendChild( link );
		}
	}

	function finish( data, jobId ) {
		running = false;

		if ( progress ) {
			progress.value = progress.max;
		}

		// Z2: baner podaje ZAIMPORTOWANE (przyjete do rejestru), tak jak kolumna
		// „Zaimportowane / wszystkie" — nie „przetworzone", ktore obejmuja odrzucone.
		var text = sprintf( cfg.i18n.done, [ data.processed, data.total, zaimportowane( data ), data.errors ] );
		var extra = data.errors > 0 ? cfg.i18n.doneErrors : '';

		show( text, extra );
		updateHistoryRow( jobId, data );

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

					paint( json.data.processed, json.data.total, json.data.errors, zaimportowane( json.data ) );

					if ( 'processing' === json.data.status ) {
						next();
						return;
					}

					finish( json.data, jobId );
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

				if ( json.data.report_url ) {
					reportUrls[ jobId ] = json.data.report_url;
				}

				paint( json.data.processed, json.data.total, json.data.errors, zaimportowane( json.data ) );
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

	if ( cfg.job && cfg.job.reportUrl ) {
		reportUrls[ cfg.job.id ] = cfg.job.reportUrl;
	}

	if ( cfg.job && cfg.job.token && 'processing' === cfg.job.status ) {
		paint( cfg.job.processed, cfg.job.total, cfg.job.errors, zaimportowane( cfg.job ) );
		loop( cfg.job.id, cfg.job.token );
	} else if ( cfg.job && 'processing' === cfg.job.status && resumeBtn ) {
		// Żywy job bez tokenu w tym oknie (np. odświeżona karta) — pokaż „Wznów".
		resumeBtn.classList.remove( 'hidden' );
	}
} )();
