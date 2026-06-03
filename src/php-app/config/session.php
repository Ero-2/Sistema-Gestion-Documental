<?php
/**
 * Session helper — verifica autenticación.
 * Incluir en index.php o cualquier página que requiera login.
 */

session_start();

// Redirigir a login si no está autenticado
if (!isset($_SESSION['user_id'])) {
    // Permitir acceso a /login.php sin autenticación
    $request_uri = $_SERVER['REQUEST_URI'];
    if (strpos($request_uri, '/login.php') === false && strpos($request_uri, '/api/auth.php') === false) {
        header('Location: ' . DMS_BASE . '/login.php');
        exit;
    }
}

// Helper para obtener info del usuario
function getCurrentUser() {
    return [
        'user_id' => $_SESSION['user_id'] ?? null,
        'user_name' => $_SESSION['user_name'] ?? 'Guest',
        'email' => $_SESSION['email'] ?? null,
        'roles' => $_SESSION['roles'] ?? [],
    ];
}

// Helper para verificar rol
function hasRole($role) {
    $user = getCurrentUser();
    return in_array($role, $user['roles'] ?? []);
}

// Helper para verificar cualquier rol
function hasAnyRole($roles) {
    $user = getCurrentUser();
    return !empty(array_intersect($roles, $user['roles'] ?? []));
}

// Helper para logout
function logout() {
    session_destroy();
    header('Location: ' . DMS_BASE . '/login.php');
    exit;
}
