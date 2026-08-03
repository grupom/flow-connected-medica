<script>
    import { onMount } from "svelte";
    import { goto } from "$app/navigation";
    import { auth } from "$lib/auth.js";
    import { api } from "$lib/api.js";
    import { toasts } from "$lib/stores.js";
    import { t, locale } from "$lib/i18n";
    import LanguageSwitcher from "$lib/components/LanguageSwitcher.svelte";

    let login = "";
    let password = "";
    let loading = false;
    let error = "";
    let multiLanguage = false;

    onMount(async () => {
        try {
            const res = await api.public.get("/api/settings");
            multiLanguage = res.data.multi_language ?? false;
            if (!multiLanguage) locale.set("es");
        } catch {
            // Non-critical — keep defaults
        }
    });

    async function handleSubmit() {
        if (!login.trim() || !password.trim()) {
            error = $t('login.error_empty');
            return;
        }
        loading = true;
        error = "";
        try {
            const res = await api.public.post("/api/auth/login", {
                login,
                password,
            });
            auth.setUser(res.user); // session cookies already set by the server

            // Si el usuario tiene un kiosco asignado, redirigir al modo kiosco
            try {
                await api.get('/api/kiosk/session');
                // Llegó aquí → es usuario kiosco
                goto('/kiosk');
                return;
            } catch {
                // No es kiosco → flujo normal
            }

            toasts.success($t('login.success', { name: res.user.display_name }));
            goto("/dashboard");
        } catch (err) {
            error = err.message || $t('login.error_failed');
        } finally {
            loading = false;
        }
    }
</script>

<svelte:head><title>{$t('login.title')}</title></svelte:head>

<div class="login-page">
    <div class="login-card">
        {#if multiLanguage}
        <div class="language-selector-wrapper">
            <LanguageSwitcher />
        </div>
        {/if}

        <div class="login-brand">
            <img src="/logo-medica.svg" alt="Médica" class="login-logo-img" />
            <p class="login-sub">{$t('login.subtitle')}</p>
        </div>

        <form class="login-form" on:submit|preventDefault={handleSubmit}>
            {#if error}
                <div class="login-error" role="alert">{error}</div>
            {/if}

            <div class="form-group">
                <label class="form-label" for="login">{$t('login.label_username')}</label>
                <input
                    id="login"
                    class="input"
                    type="text"
                    bind:value={login}
                    placeholder={$t('login.placeholder_username')}
                    autocomplete="username"
                    disabled={loading}
                />
            </div>

            <div class="form-group">
                <label class="form-label" for="password">{$t('login.label_password')}</label>
                <input
                    id="password"
                    class="input"
                    type="password"
                    bind:value={password}
                    placeholder="••••••••"
                    autocomplete="current-password"
                    disabled={loading}
                />
            </div>

            <button
                class="btn btn-primary btn-lg login-btn"
                type="submit"
                disabled={loading}
            >
                {#if loading}<span class="btn-spinner"></span>{/if}
                {loading ? $t('login.button_signing_in') : $t('login.button_signin')}
            </button>
        </form>

        <div class="powered-by">
            <span class="pb-line"></span>
            <span class="pb-text">Powered by Flow Connected</span>
            <span class="pb-line"></span>
        </div>
    </div>
</div>

<style>
    .login-page {
        min-height: 100vh;
        display: flex;
        align-items: center;
        justify-content: center;
        background: linear-gradient(
            135deg,
            #dbeafe 0%,
            #ede9fe 50%,
            #d1fae5 100%
        );
        padding: 24px;
    }

    .login-card {
        background: var(--surface);
        border-radius: var(--radius-xl);
        box-shadow: var(--shadow-xl);
        padding: 40px 40px 36px;
        width: 100%;
        max-width: 420px;
        animation: fadeIn 0.3s ease;
    }

    .login-brand {
        text-align: center;
        margin-bottom: 32px;
    }

    .language-selector-wrapper {
        display: flex;
        justify-content: flex-end;
        margin-bottom: 24px;
        margin-top: -16px;
        margin-right: -16px;
    }
    
    .login-logo-img {
        height: 90px;
        width: auto;
        display: block;
        margin: 0 auto 16px;
    }
    .login-sub {
        color: var(--text-muted);
        font-size: 0.875rem;
        margin-top: 4px;
    }
    .powered-by {
        display: flex;
        align-items: center;
        gap: 10px;
        margin-top: 24px;
    }
    .pb-line {
        flex: 1;
        height: 1px;
        background: var(--border);
    }
    .pb-text {
        font-size: 0.7rem;
        color: var(--text-muted);
        white-space: nowrap;
        letter-spacing: 0.03em;
    }

    .login-form {
        display: flex;
        flex-direction: column;
        gap: 18px;
    }

    .login-error {
        background: var(--danger-light);
        color: #b91c1c;
        border: 1px solid #fca5a5;
        border-radius: var(--radius-sm);
        padding: 10px 14px;
        font-size: 0.875rem;
        font-weight: 500;
    }

    .login-btn {
        width: 100%;
        justify-content: center;
    }

    .btn-spinner {
        width: 14px;
        height: 14px;
        border: 2px solid rgba(255, 255, 255, 0.4);
        border-top-color: #fff;
        border-radius: 50%;
        animation: spin 0.6s linear infinite;
        display: inline-block;
    }
    @keyframes spin {
        to {
            transform: rotate(360deg);
        }
    }
</style>
