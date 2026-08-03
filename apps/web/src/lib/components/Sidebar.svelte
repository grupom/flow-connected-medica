<script>
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import { auth } from '$lib/auth.js';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';
  import { adminT as t } from '$lib/i18n';

  const topNavConfig = [
    { href: '/dashboard',         key: 'nav.dashboard',      icon: '📊', roles: null },
    { href: '/front-desk',        key: 'nav.front_desk',     icon: '⚡', roles: ['ADMIN', 'DESK'] },
    { href: '/station',           key: 'nav.station_ops',    icon: '🎫', roles: null },
    { href: '/admin/boards',      key: 'nav.display_boards', icon: '📺', roles: ['ADMIN'] },
    { href: '/admin/reports',     key: 'nav.reports',        icon: '📉', roles: ['ADMIN'] },
    { href: '/admin/daily-close', key: 'nav.daily_close',    icon: '📅', roles: ['ADMIN', 'SUPERVISOR'] },
  ];

  $: userRoles = $auth.user?.role_codes || [];
  $: filteredTopNav = topNavConfig
    .filter(item => !item.roles || item.roles.some(r => userRoles.includes(r)))
    .map(item => ({ ...item, label: $t(item.key) }));
  $: isAdmin = userRoles.includes('ADMIN');

  async function handleLogout() {
    try {
      // No token to read/send — the refresh cookie rides along automatically.
      await api.post('/api/auth/logout', {}).catch(() => {});
    } finally {
      auth.logout();
      goto('/login');
    }
  }

  $: currentPath = $page.url.pathname;

  // Settings is active on any /admin/* route
  $: settingsActive = currentPath.startsWith('/admin/');
</script>

<aside class="sidebar">
  <!-- Brand -->
  <div class="brand">
    <img src="/logo-medica.svg" alt="Médica" class="brand-logo" />
    <span class="brand-fc">Flow Connected</span>
  </div>

  <div class="divider" style="margin: 0 16px;"></div>

  <!-- Nav -->
  <nav class="nav">
    {#each filteredTopNav as item}
      <a
        href={item.href}
        class="nav-item"
        class:active={currentPath.startsWith(item.href)}
        aria-label={item.label}
      >
        <span class="nav-icon">{item.icon}</span>
        <span class="nav-label">{item.label}</span>
      </a>
    {/each}

    {#if isAdmin}
      <div class="divider" style="margin: 8px 16px; border-bottom: 1px solid var(--border);"></div>
      <a
        href="/admin/settings"
        class="nav-item"
        class:active={settingsActive}
        aria-label={$t('nav.settings')}
      >
        <span class="nav-icon">⚙️</span>
        <span class="nav-label">{$t('nav.settings')}</span>
      </a>
    {/if}
  </nav>

  <!-- Footer -->
  <div class="sidebar-footer">
    <a href="/docs" target="_blank" rel="noopener" class="nav-item">
      <span class="nav-icon">📖</span>
      <span class="nav-label">{$t('nav.documentation')}</span>
    </a>
    <a href="/profile" class="nav-item" class:active={currentPath === '/profile'}>
      <span class="nav-icon">👤</span>
      <span class="nav-label">{$t('nav.my_profile')}</span>
    </a>
    <button class="nav-item logout-btn" on:click={handleLogout}>
      <span class="nav-icon">🚪</span>
      <span class="nav-label">{$t('nav.logout')}</span>
    </button>
  </div>
</aside>

<style>
.sidebar {
  position: fixed;
  top: 0; left: 0;
  width: var(--sidebar-w);
  height: 100vh;
  background: var(--sidebar-bg);
  border-right: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  z-index: var(--z-sidebar);
  overflow-y: auto;
}

.brand {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 4px;
  padding: 20px 16px 16px;
}
.brand-logo { height: 40px; width: auto; display: block; }
.brand-fc {
  font-size: 0.6rem;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--text-muted);
  opacity: 0.7;
}

.nav {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: 8px;
  flex: 1;
}

.nav-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 9px 12px;
  border-radius: var(--radius-sm);
  font-size: .875rem;
  font-weight: 500;
  color: var(--text-muted);
  cursor: pointer;
  text-decoration: none;
  transition: background var(--transition), color var(--transition);
  border: none;
  font-family: inherit;
  width: 100%;
  text-align: left;
}
.nav-item:hover { background: var(--sidebar-hover); color: var(--primary); }
.nav-item.active { background: var(--primary-light); color: var(--primary-dark); font-weight: 600; }

.nav-icon  { font-size: 1.1rem; width: 20px; text-align: center; flex-shrink: 0; }
.nav-label { white-space: nowrap; }

.sidebar-footer { padding: 8px; border-top: 1px solid var(--border); }
.logout-btn { color: var(--danger); }
.logout-btn:hover { background: var(--danger-light); color: var(--danger); }

.divider { border-bottom: 1px solid var(--border); }

@media (max-width: 768px) {
  .sidebar { display: none; }
}
</style>
