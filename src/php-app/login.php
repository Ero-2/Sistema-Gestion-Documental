<?php
session_start();

// Si ya está autenticado, redirigir
if (isset($_SESSION['user_id'])) {
    header('Location: /');
    exit;
}

$error = '';
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login — PublicDMS</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        .login-card {
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            width: 100%;
            max-width: 400px;
            padding: 40px;
        }
        .login-header {
            text-align: center;
            margin-bottom: 30px;
        }
        .login-header h1 {
            font-size: 28px;
            font-weight: 700;
            color: #333;
            margin-bottom: 5px;
        }
        .login-header p {
            color: #999;
            font-size: 14px;
        }
        .form-control {
            border-radius: 8px;
            border: 1px solid #ddd;
            padding: 12px 15px;
            font-size: 14px;
            margin-bottom: 15px;
        }
        .form-control:focus {
            border-color: #667eea;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
        }
        .btn-login {
            width: 100%;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 12px;
            border-radius: 8px;
            font-weight: 600;
            font-size: 15px;
            cursor: pointer;
            transition: transform 0.2s;
        }
        .btn-login:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3);
            color: white;
        }
        .btn-login:disabled {
            opacity: 0.7;
            cursor: not-allowed;
            transform: none;
        }
        .alert-danger {
            border-radius: 8px;
            margin-bottom: 20px;
            border: none;
            background: #f8d7da;
            color: #721c24;
        }
        .spinner-border {
            display: none;
            width: 16px;
            height: 16px;
            margin-right: 8px;
        }
        .spinner-border.show {
            display: inline-block;
        }
        .loading .btn-login:disabled {
            pointer-events: none;
        }
    </style>
</head>
<body>

<div class="login-card">
    <div class="login-header">
        <h1>PublicDMS</h1>
        <p>Sistema de Gestión Documental</p>
    </div>

    <?php if ($error): ?>
        <div class="alert alert-danger alert-dismissible fade show" role="alert">
            <?php echo htmlspecialchars($error); ?>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    <?php endif; ?>

    <form id="loginForm">
        <div class="mb-3">
            <label for="email" class="form-label">Email</label>
            <input type="email" class="form-control" id="email" name="email" required placeholder="usuario@example.com">
        </div>

        <div class="mb-3">
            <label for="password" class="form-label">Contraseña</label>
            <input type="password" class="form-control" id="password" name="password" required placeholder="••••••••">
        </div>

        <button type="submit" class="btn btn-login" id="submitBtn">
            <span class="spinner-border" role="status" aria-hidden="true"></span>
            Iniciar Sesión
        </button>
    </form>

    <div style="text-align: center; margin-top: 20px; color: #999; font-size: 12px;">
        <p>Sistema de autenticación centralizado.</p>
        <p>Credenciales validadas por servidor central.</p>
    </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<script>
document.getElementById('loginForm').addEventListener('submit', async (e) => {
    e.preventDefault();

    const email = document.getElementById('email').value;
    const password = document.getElementById('password').value;
    const submitBtn = document.getElementById('submitBtn');
    const spinner = submitBtn.querySelector('.spinner-border');

    // Mostrar spinner
    submitBtn.disabled = true;
    spinner.classList.add('show');

    try {
        const response = await fetch('/api/auth.php?action=login', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ email, password })
        });

        const data = await response.json();

        if (response.ok) {
            // Login exitoso
            window.location.href = data.redirect || '/';
        } else {
            // Error
            alert(data.error || 'Error en autenticación');
            submitBtn.disabled = false;
            spinner.classList.remove('show');
        }
    } catch (error) {
        alert('Error de conexión: ' + error.message);
        submitBtn.disabled = false;
        spinner.classList.remove('show');
    }
});
</script>

</body>
</html>
