<?php
/**
 * Bootstrap — se ejecuta antes de cada request (auto_prepend_file vía Nginx).
 * Define DMS_BASE = prefijo público cuando se sirve detrás de Nginx por path (/php).
 * Acceso directo (sin header) → DMS_BASE = '' → rutas raíz normales.
 */
if (!defined('DMS_BASE')) {
    $p = $_SERVER['HTTP_X_FORWARDED_PREFIX'] ?? '';
    define('DMS_BASE', rtrim($p, '/'));
}
