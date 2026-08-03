<script>
  export let title = '';
  import { auth } from '$lib/auth.js';
  import { adminLocale } from '$lib/i18n';
  import { systemSettings } from '$lib/stores.js';
  import LanguageSwitcher from '$lib/components/LanguageSwitcher.svelte';

  $: user = $auth.user;
  $: initials = user?.display_name
    ? user.display_name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase()
    : '?';
  $: roleLabel = user?.role_codes?.join(', ') ?? '';
</script>

<header class="topbar">
  <div class="topbar-left">
    <h1 class="topbar-title">{title}</h1>
  </div>
  <div class="topbar-right">
    {#if $systemSettings.multi_language}
      <LanguageSwitcher localeStore={adminLocale} />
    {/if}
    {#if user}
      <div class="user-chip">
        <div class="user-avatar">{initials}</div>
        <div class="user-info">
          <span class="user-name">{user.display_name}</span>
          {#if roleLabel}
            <span class="user-role">{roleLabel}</span>
          {/if}
        </div>
      </div>
    {/if}
  </div>
</header>

<style>
.topbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 32px;
  height: 64px;
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  position: sticky;
  top: 0;
  z-index: 50;
}

.topbar-title {
  font-size: 1.125rem;
  font-weight: 700;
  color: var(--text);
}

.topbar-right { display: flex; align-items: center; gap: 12px; }

.user-chip {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 6px 14px 6px 8px;
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: var(--radius-pill);
  cursor: default;
}

.user-avatar {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--primary), var(--purple));
  color: #fff;
  font-size: .75rem;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.user-info { display: flex; flex-direction: column; }
.user-name { font-size: .8125rem; font-weight: 600; color: var(--text); line-height: 1.2; }
.user-role { font-size: .7rem; color: var(--text-muted); }

@media (max-width: 768px) {
  .topbar { padding: 0 16px; }
  .user-info { display: none; }
}
</style>
