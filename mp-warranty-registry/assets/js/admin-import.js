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
	var running = false;

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

		show(
			sprintf( cfg.i18n.done, [ data.processed, data.total, data.errors ] ),
			data.errors > 0 ? cfg.i18n.doneErrors : ''
		);
	}

	function fail( text ) {
		running = false;
		show( text );

		if ( resumeBtn ) {
			resumeBtn.classList.remove( 'hidden' );
		}
	}

	function loop( jobId, token ) {
		if ( running ) {
			return;
		}

		running = true;

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

	function reclaim( jobId ) {
		show( cfg.i18n.resuming );

		post( 'mp_import_reclaim', { job_id: jobId } )
			.then( function ( json ) {
				if ( ! json || ! json.success ) {
					fail( json && json.data && json.data.message ? json.data.message : cfg.i18n.netError );
					return;
				}

				paint( json.data.processed, json.data.total, json.data.errors );
				loop( jobId, json.data.token );
			} )
			.catch( function () {
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
