<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { auth } from '$lib/auth.js';
  import { goto } from '$app/navigation';

  let loginData = '';
  let password = '';
  let error = '';
  let loading = false;

  onMount(() => {
    const unsub = auth.subscribe(state => {
      if (state?.user) goto('/kiosk');
    });
    return unsub;
  });

  async function handleLogin() {
    error = '';
    loading = true;
    try {
      const res = await api.public.post('/api/auth/login', { login: loginData, password });
      
      auth.setAuth({
          user: res.user,
          accessToken: res.accessToken,
          refreshToken: res.refreshToken,
      });

      // Optional: Check if the user is actually bound to a Kiosk by hitting the session endpoint
      try {
        await api.get('/api/kiosk/session');
        goto('/kiosk');
      } catch (kioskErr) {
        auth.logout();
        error = 'Este usuario no tiene un kiosco asignado o está inactivo.';
      }
    } catch (err) {
      error = err.message || 'Credenciales inválidas';
    } finally {
      loading = false;
    }
  }
</script>

<svelte:head>
  <title>Acceso Kiosco — Flow Connected</title>
</svelte:head>

<main class="kiosk-login-root fade-in">
  <div class="login-box card">
    <div class="k-brand-center">
      <img src="/logo-medica.svg" alt="Médica" class="k-logo-img" />
      <p class="k-sub">Acceso para Estaciones de Autogestión</p>
    </div>

    {#if error}
      <div class="error-banner">{error}</div>
    {/if}

    <form on:submit|preventDefault={handleLogin} class="login-form">
      <div class="form-group">
        <label for="login" class="form-label">Usuario Kiosco / Email</label>
        <input 
          id="login" 
          type="text" 
          class="input" 
          bind:value={loginData} 
          required 
          autocomplete="username" 
          placeholder="Ej: kiosk_lobby" 
        />
      </div>

      <div class="form-group">
        <label for="password" class="form-label">Contraseña</label>
        <input 
          id="password" 
          type="password" 
          class="input" 
          bind:value={password} 
          required 
          autocomplete="current-password" 
        />
      </div>

      <button type="submit" class="btn btn-primary btn-lg submit-btn" disabled={loading}>
        {loading ? 'Validando Terminal...' : 'Iniciar Sesión Módulo'}
      </button>
    </form>
    
    <div class="footer-links">
      <a href="/login">Ir a Plataforma Operativa</a>
    </div>

    <div class="powered-by">
      <span class="pb-line"></span>
      <span class="pb-text">Powered by Flow Connected</span>
      <span class="pb-line"></span>
    </div>
  </div>
</main>

<style>
  :global(body) { margin: 0; }
  
  .kiosk-login-root {
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--bg);
    padding: 24px;
    font-family: 'Inter', system-ui, sans-serif;
  }

  .login-box {
    width: 100%;
    max-width: 460px;
    padding: 48px 40px;
    border-radius: var(--radius-xl);
    box-shadow: var(--shadow-xl);
  }

  .k-brand-center {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    margin-bottom: 32px;
  }

  .k-logo-img { height: 60px; width: auto; display: block; margin: 0 auto 12px; }
  .k-title { margin: 0; font-size: 1.8rem; font-weight: 800; color: var(--text); letter-spacing: -0.5px; }
  .k-sub { margin: 4px 0 0; font-size: .95rem; color: var(--text-muted); font-weight: 500; }

  .error-banner {
    background: var(--danger-light);
    color: var(--danger);
    padding: 12px 16px;
    border-radius: var(--radius-sm);
    font-size: .9rem;
    font-weight: 500;
    margin-bottom: 24px;
    text-align: center;
    border: 1px solid rgba(239,68,68,0.3);
  }

  .login-form {
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .submit-btn {
    margin-top: 12px;
    width: 100%;
    justify-content: center;
  }

  .footer-links {
    margin-top: 32px;
    border-top: 1px solid var(--border);
    padding-top: 24px;
    text-align: center;
    font-size: .85rem;
  }
  .footer-links a { color: var(--text-muted); text-decoration: none; font-weight: 500; transition: color 0.15s; }
  .footer-links a:hover { color: var(--primary); }
  .powered-by {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-top: 20px;
  }
  .pb-line { flex: 1; height: 1px; background: var(--border); }
  .pb-text { font-size: 0.68rem; color: var(--text-muted); white-space: nowrap; letter-spacing: 0.03em; }
</style>
