<?php
/**
 * API de Autenticación para PHP.
 * Consume endpoint de validación de .NET.
 * POST /api/auth.php?action=login
 */

header('Content-Type: application/json; charset=utf-8');

$action = $_GET['action'] ?? null;

// Logout — GET es válido (enlace de navegación)
if ($action === 'logout') {
    session_start();
    session_destroy();
    header('Location: /login.php');
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid JSON']);
    exit;
}

if ($action !== 'login') {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid action']);
    exit;
}

try {
    // Validar email y password
    $email = $input['email'] ?? null;
    $password = $input['password'] ?? null;

    if (!$email || !$password) {
        http_response_code(400);
        echo json_encode(['error' => 'Missing email or password']);
        exit;
    }

    // Llamar a API de validación en .NET
    $dotnetUrl = getenv('DOTNET_API_URL') ?: 'http://dotnet:8080';
    $url = "$dotnetUrl/api/v1/auth/validate";

    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode([
        'email' => $email,
        'password' => $password
    ]));
    curl_setopt($ch, CURLOPT_TIMEOUT, 5);

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpCode === 401) {
        http_response_code(401);
        echo json_encode(['error' => 'Invalid credentials']);
        exit;
    }

    if ($httpCode !== 200) {
        http_response_code(500);
        echo json_encode(['error' => 'Authentication service error']);
        error_log("[Auth] .NET returned $httpCode");
        exit;
    }

    // Parsear respuesta
    $userData = json_decode($response, true);
    if (!$userData || !isset($userData['userId'])) {
        http_response_code(500);
        echo json_encode(['error' => 'Invalid response from auth service']);
        exit;
    }

    // Iniciar sesión
    session_start();
    $_SESSION['user_id'] = $userData['userId'];
    $_SESSION['user_name'] = $userData['userName'];
    $_SESSION['email'] = $userData['email'];
    $_SESSION['roles'] = $userData['roles'] ?? [];
    $_SESSION['login_time'] = time();

    http_response_code(200);
    echo json_encode([
        'status' => 'success',
        'user_id' => $userData['userId'],
        'user_name' => $userData['userName'],
        'email' => $userData['email'],
        'roles' => $userData['roles'],
        'redirect' => '/'
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => $e->getMessage()]);
    error_log("[Auth] Error: " . $e->getMessage());
}
