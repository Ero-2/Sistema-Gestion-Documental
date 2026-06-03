<?php
session_start();

// Si ya está autenticado, redirigir
if (isset($_SESSION['user_id'])) {
    header('Location: ' . DMS_BASE . '/');
    exit;
}

$error = '';
?>
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PublicDMS · registro oficial</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
:root {
  /* superficies — papel hueso, elevación clara (sube hacia blanco cálido) */
  --paper: #efece4;
  --card:  #f8f6f0;
  --field: #eae6dc;   /* inset — un punto más oscuro = papel marcado para escribir */
  /* tinta de archivo — jerarquía de texto */
  --ink-1: #2a2622;
  --ink-2: #5c554c;
  --ink-3: #8a8175;
  --ink-4: #b3a99a;
  /* teal-sello — marca: válido / controlado / aprobado (único acento) */
  --seal:        #0f8a73;
  --seal-bright: #18bc9c;
  --seal-dim:    rgba(15,138,115,0.10);
  /* semántico de estado */
  --vigente:  #2f8f6b;
  --vencer:   #b9772a;
  --danger:   #b0473f;
  --danger-dim: rgba(176,71,63,0.10);
  /* bordes — tinta baja opacidad, desaparecen hasta que se necesitan */
  --bd-1: rgba(42,38,34,0.08);
  --bd-2: rgba(42,38,34,0.14);
  --bd-3: rgba(42,38,34,0.24);
  --mono: 'IBM Plex Mono', ui-monospace, monospace;
  --sans: 'IBM Plex Sans', system-ui, sans-serif;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { height: 100%; }
body {
  background: var(--paper);
  color: var(--ink-1);
  font-family: var(--sans);
  font-size: 14px; line-height: 1.5;
  -webkit-font-smoothing: antialiased;
  display: flex; align-items: center; justify-content: center;
  /* pauta de archivo casi imperceptible — textura de papel rayado */
  background-image: repeating-linear-gradient(transparent, transparent 43px, var(--bd-1) 43px, var(--bd-1) 44px);
}
::selection { background: var(--seal-dim); }

.sheet {
  width: 100%; max-width: 380px; margin: 24px;
  background: var(--card);
  border: 1px solid var(--bd-2);
  border-radius: 6px;
  overflow: hidden;
}

/* ── Encabezado — membrete del registro ───────────────── */
.sheet-head {
  padding: 22px 22px 18px;
  border-bottom: 1px solid var(--bd-2);
}
.mark { display: flex; align-items: center; gap: 11px; }
.stamp {
  width: 30px; height: 30px; flex: none;
  display: flex; align-items: center; justify-content: center;
  border: 1.5px solid var(--seal); border-radius: 5px;
  color: var(--seal); font-size: 15px; font-weight: 700;
}
.mark .name { font-size: 17px; font-weight: 700; letter-spacing: -0.01em; }
.mark .name .pub { color: var(--ink-1); }
.mark .name .dms { color: var(--seal); }
.tagline {
  margin-top: 12px; font-family: var(--mono); font-size: 11px;
  color: var(--ink-3); text-transform: uppercase; letter-spacing: 0.1em;
}

/* ── Cuerpo ───────────────────────────────────────────── */
.sheet-body { padding: 22px; }
.field { margin-bottom: 16px; }
.field label {
  display: block; font-family: var(--mono); font-size: 10px;
  text-transform: uppercase; letter-spacing: 0.1em; color: var(--ink-3);
  margin-bottom: 7px;
}
.field input {
  width: 100%; height: 42px; padding: 0 13px;
  background: var(--field); color: var(--ink-1);
  font-family: var(--mono); font-size: 13px;
  border: 1px solid var(--bd-2); border-radius: 5px;
  outline: none; transition: border-color .12s ease;
}
.field input::placeholder { color: var(--ink-4); }
.field input:focus { border-color: var(--seal); }

.btn-enter {
  width: 100%; height: 44px; margin-top: 4px;
  display: flex; align-items: center; justify-content: center; gap: 8px;
  font-family: var(--sans); font-size: 14px; font-weight: 600; letter-spacing: 0.01em;
  color: #fff; background: var(--seal);
  border: 1px solid var(--seal); border-radius: 5px;
  cursor: pointer; transition: background .12s ease, opacity .12s ease;
}
.btn-enter:hover:not(:disabled) { background: #0c7a66; }
.btn-enter:disabled { opacity: 0.55; cursor: not-allowed; }
.btn-enter .arrow { transition: transform .12s ease; }
.btn-enter:hover:not(:disabled) .arrow { transform: translateX(3px); }

/* línea de estado — feedback de consulta */
.status {
  font-family: var(--mono); font-size: 11px; min-height: 17px;
  margin-top: 15px; color: var(--ink-3);
}
.status.err { color: var(--danger); }
.status.err::before { content: '! '; }
.status.run::before { content: '› '; color: var(--seal); }

/* ── Pie — nota de autenticación ──────────────────────── */
.sheet-foot {
  padding: 13px 22px;
  border-top: 1px solid var(--bd-1);
  font-family: var(--mono); font-size: 10px; color: var(--ink-4);
  display: flex; align-items: center; gap: 8px;
}
.sheet-foot .dot { color: var(--bd-3); }
</style>
</head>
<body>

<form class="sheet" id="loginForm" autocomplete="on">
  <div class="sheet-head">
    <div class="mark">
      <span class="stamp">&#10003;</span>
      <span class="name"><span class="pub">Public</span><span class="dms">DMS</span></span>
    </div>
    <div class="tagline">consulta de documentos controlados</div>
  </div>

  <div class="sheet-body">
    <?php if ($error): ?>
      <div class="status err" style="margin:0 0 14px;"><?php echo htmlspecialchars($error); ?></div>
    <?php endif; ?>

    <div class="field">
      <label for="email">credencial</label>
      <input type="email" id="email" name="email" required spellcheck="false"
             autocomplete="username" placeholder="usuario@qualitydms.local">
    </div>

    <div class="field">
      <label for="password">clave</label>
      <input type="password" id="password" name="password" required
             autocomplete="current-password" placeholder="&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;">
    </div>

    <button type="submit" class="btn-enter" id="submitBtn">
      <span id="btnTxt">Acceder al registro</span><span class="arrow">&rsaquo;</span>
    </button>

    <div class="status" id="status"></div>
  </div>

  <div class="sheet-foot">
    <span>autenticación centralizada</span>
    <span class="dot">·</span>
    <span>validación: servidor SGC</span>
  </div>
</form>

<script>
const form   = document.getElementById('loginForm');
const btn    = document.getElementById('submitBtn');
const btnTxt = document.getElementById('btnTxt');
const status = document.getElementById('status');

function setStatus(msg, cls) {
  status.className = 'status' + (cls ? ' ' + cls : '');
  status.textContent = msg;
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const email = document.getElementById('email').value.trim();
  const password = document.getElementById('password').value;

  btn.disabled = true;
  btnTxt.textContent = 'Verificando';
  setStatus('validando credenciales…', 'run');

  try {
    const response = await fetch('<?= DMS_BASE ?>/api/auth.php?action=login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    });
    const data = await response.json();

    if (response.ok) {
      setStatus('acceso concedido — abriendo registro…', 'run');
      window.location.href = data.redirect || '<?= DMS_BASE ?>/';
    } else {
      setStatus(data.error || 'credenciales inválidas', 'err');
      btn.disabled = false; btnTxt.textContent = 'Acceder al registro';
    }
  } catch (error) {
    setStatus('error de conexión — ' + error.message, 'err');
    btn.disabled = false; btnTxt.textContent = 'Acceder al registro';
  }
});
</script>

</body>
</html>
