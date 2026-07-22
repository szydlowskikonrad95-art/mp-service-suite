<?php
/**
 * TEST-FIXTURE: minimalny drop-in object-cache (persistent object cache ON).
 *
 * Sprawia, ze `wp_using_ext_object_cache()` == true — testujemy sciezke
 * „zewnetrzny cache obecny" (dirty-env DoD C §4): nasz kod nie moze Fatalowac
 * ani sypac notice, gdy transienty ida przez cache zamiast wp_options.
 * In-memory (per-request) — wystarczy do wykrycia Fatal/notice; NIE wchodzi
 * do artefaktu pluginu (to fixture testowy).
 *
 * @package MP\Test
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Minimalny cache w pamieci procesu.
 */
class WP_Object_Cache {

	/** @var array<string, mixed> */
	private array $data = array();

	/** @var array<string, bool> */
	public array $global_groups = array();

	/** @var array<string, bool> */
	public array $non_persistent_groups = array();

	private function key( string $key, string $group ): string {
		return ( '' === $group ? 'default' : $group ) . ':' . $key;
	}

	public function add( $key, $data, $group = 'default', $expire = 0 ) {
		$k = $this->key( (string) $key, (string) $group );
		if ( array_key_exists( $k, $this->data ) ) {
			return false;
		}
		$this->data[ $k ] = $data;
		return true;
	}

	public function set( $key, $data, $group = 'default', $expire = 0 ) {
		$this->data[ $this->key( (string) $key, (string) $group ) ] = $data;
		return true;
	}

	public function get( $key, $group = 'default', $force = false, &$found = null ) {
		$k = $this->key( (string) $key, (string) $group );
		if ( array_key_exists( $k, $this->data ) ) {
			$found = true;
			return $this->data[ $k ];
		}
		$found = false;
		return false;
	}

	public function delete( $key, $group = 'default' ) {
		unset( $this->data[ $this->key( (string) $key, (string) $group ) ] );
		return true;
	}

	public function replace( $key, $data, $group = 'default', $expire = 0 ) {
		$k = $this->key( (string) $key, (string) $group );
		if ( ! array_key_exists( $k, $this->data ) ) {
			return false;
		}
		$this->data[ $k ] = $data;
		return true;
	}

	public function incr( $key, $offset = 1, $group = 'default' ) {
		$k   = $this->key( (string) $key, (string) $group );
		$val = (int) ( $this->data[ $k ] ?? 0 ) + (int) $offset;
		$this->data[ $k ] = $val;
		return $val;
	}

	public function decr( $key, $offset = 1, $group = 'default' ) {
		$k   = $this->key( (string) $key, (string) $group );
		$val = (int) ( $this->data[ $k ] ?? 0 ) - (int) $offset;
		$this->data[ $k ] = $val;
		return $val;
	}

	public function flush() {
		$this->data = array();
		return true;
	}

	public function add_global_groups( $groups ) {
		foreach ( (array) $groups as $g ) {
			$this->global_groups[ $g ] = true;
		}
	}

	public function add_non_persistent_groups( $groups ) {
		foreach ( (array) $groups as $g ) {
			$this->non_persistent_groups[ $g ] = true;
		}
	}

	public function switch_to_blog( $blog_id ) {}
	public function close() {
		return true;
	}
}

/**
 * Globalny akcesor cache.
 *
 * @return WP_Object_Cache
 */
function wp_cache_get_instance(): WP_Object_Cache {
	global $wp_object_cache;
	if ( ! ( $wp_object_cache instanceof WP_Object_Cache ) ) {
		$wp_object_cache = new WP_Object_Cache();
	}
	return $wp_object_cache;
}

function wp_cache_init() {
	wp_cache_get_instance();
}
function wp_cache_add( $key, $data, $group = '', $expire = 0 ) {
	return wp_cache_get_instance()->add( $key, $data, $group, (int) $expire );
}
function wp_cache_set( $key, $data, $group = '', $expire = 0 ) {
	return wp_cache_get_instance()->set( $key, $data, $group, (int) $expire );
}
function wp_cache_get( $key, $group = '', $force = false, &$found = null ) {
	return wp_cache_get_instance()->get( $key, $group, $force, $found );
}
function wp_cache_delete( $key, $group = '' ) {
	return wp_cache_get_instance()->delete( $key, $group );
}
function wp_cache_replace( $key, $data, $group = '', $expire = 0 ) {
	return wp_cache_get_instance()->replace( $key, $data, $group, (int) $expire );
}
function wp_cache_incr( $key, $offset = 1, $group = '' ) {
	return wp_cache_get_instance()->incr( $key, $offset, $group );
}
function wp_cache_decr( $key, $offset = 1, $group = '' ) {
	return wp_cache_get_instance()->decr( $key, $offset, $group );
}
function wp_cache_flush() {
	return wp_cache_get_instance()->flush();
}
function wp_cache_flush_runtime() {
	return wp_cache_get_instance()->flush();
}
function wp_cache_add_global_groups( $groups ) {
	wp_cache_get_instance()->add_global_groups( $groups );
}
function wp_cache_add_non_persistent_groups( $groups ) {
	wp_cache_get_instance()->add_non_persistent_groups( $groups );
}
function wp_cache_switch_to_blog( $blog_id ) {
	wp_cache_get_instance()->switch_to_blog( $blog_id );
}
function wp_cache_close() {
	return true;
}
function wp_cache_supports( $feature ) {
	return false;
}
