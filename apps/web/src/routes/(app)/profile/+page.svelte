<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { auth } from '$lib/auth.js';
  import { toasts } from '$lib/stores.js';

  let profile = null;
  let loading = true;

  // Edit state
  let displayName = '';
  let email = '';
  let phone = '';
  let saving = false;

  // Password state
  let currentPassword = '';
  let newPassword = '';
  let confirmPassword = '';
  let changingPassword = false;
  let showPasswordSection = false;

  async function loadProfile() {
    loading = true;
    try {
      const res = await api.get('/api/profile');
      profile = res?.data ?? res;
      displayName = profile.display_name || '';
      email = profile.email || '';
      phone = profile.phone || '';
    } catch (e) {
      toasts.error(e.message || 'Error al cargar perfil');
    } finally {
      loading = false;
    }
  }

  async function saveProfile() {
    saving = true;
    try {
      const res = await api.put('/api/profile', {
        display_name: displayName.trim(),
        email: email.trim() || null,
        phone: phone.trim() || null,
      });
      const updated = res?.data ?? res;
      profile = { ...profile, ...updated };
      toasts.success('Perfil actualizado ✓');

      // Update auth store display_name
      auth.setUser({ ...$auth.user, display_name: updated.display_name, email: updated.email, phone: updated.phone });
    } catch (e) {
      toasts.error(e.message || 'Error al guardar');
    } finally {
      saving = false;
    }
  }

  async function changePassword() {
    if (newPassword !== confirmPassword) {
      toasts.error('Las contraseñas no coinciden');
      return;
    }
    if (newPassword.length < 6) {
      toasts.error('La nueva contraseña debe tener al menos 6 caracteres');
      return;
    }
    changingPassword = true;
    try {
      await api.put('/api/profile/password', {
        current_password: currentPassword,
        new_password: newPassword,
      });
      toasts.success('Contraseña actualizada ✓');
      currentPassword = '';
      newPassword = '';
      confirmPassword = '';
      showPasswordSection = false;
    } catch (e) {
      toasts.error(e.message || 'Error al cambiar contraseña');
    } finally {
      changingPassword = false;
    }
  }

  onMount(loadProfile);
</script>

<svelte:head>
  <title>Mi Perfil — Flow Connected</title>
</svelte:head>

<div class="profile-page">
  <div class="page-header">
    <h2 class="page-title">Mi Perfil</h2>
    <p class="page-subtitle">Administre su información personal</p>
  </div>

  {#if loading}
    <div class="loading-state">
      <div class="spinner"></div>
      <p>Cargando perfil…</p>
    </div>
  {:else if profile}
    <div class="profile-grid">

      <!-- Profile Info Card -->
      <div class="card profile-card">
        <div class="card-body">
          <div class="profile-avatar">
            <span class="avatar-circle">
              {(profile.display_name || profile.username || '?').charAt(0).toUpperCase()}
            </span>
            <div class="avatar-info">
              <h3 class="avatar-name">{profile.display_name || profile.username}</h3>
              <p class="avatar-username">@{profile.username}</p>
              {#if profile.roles?.length}
                <div class="role-tags">
                  {#each profile.roles as r}
                    <span class="role-tag">{r.role_name || r.role_code}</span>
                  {/each}
                </div>
              {/if}
            </div>
          </div>

          <div class="profile-meta">
            {#if profile.last_login_at}
              <div class="meta-item">
                <span class="meta-label">Último acceso</span>
                <span class="meta-value">{new Date(profile.last_login_at).toLocaleString('es-DO')}</span>
              </div>
            {/if}
            <div class="meta-item">
              <span class="meta-label">Registrado</span>
              <span class="meta-value">{new Date(profile.created_at).toLocaleDateString('es-DO')}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Edit Form -->
      <div class="card edit-card">
        <div class="card-body">
          <h3 class="section-title">Información Personal</h3>

          <form on:submit|preventDefault={saveProfile}>
            <div class="form-group">
              <label class="form-label" for="prof-name">Nombre para mostrar</label>
              <input id="prof-name" class="input" type="text" bind:value={displayName} placeholder="Dr. Juan Pérez" />
            </div>

            <div class="form-group">
              <label class="form-label" for="prof-email">Correo electrónico</label>
              <input id="prof-email" class="input" type="email" bind:value={email} placeholder="juan@clinica.com" />
            </div>

            <div class="form-group">
              <label class="form-label" for="prof-phone">Teléfono</label>
              <input id="prof-phone" class="input" type="tel" bind:value={phone} placeholder="809-555-1234" />
            </div>

            <div class="form-group">
              <label class="form-label" for="prof-username">Usuario</label>
              <input id="prof-username" class="input input-readonly" type="text" value={profile.username} disabled />
              <small class="muted text-sm">El nombre de usuario no se puede cambiar</small>
            </div>

            <div class="form-actions">
              <button type="submit" class="btn btn-primary" disabled={saving}>
                {saving ? 'Guardando…' : 'Guardar Cambios'}
              </button>
            </div>
          </form>
        </div>
      </div>

      <!-- Password Section -->
      <div class="card password-card">
        <div class="card-body">
          <div class="pw-header">
            <h3 class="section-title">Seguridad</h3>
            {#if !showPasswordSection}
              <button class="btn btn-ghost btn-sm" on:click={() => showPasswordSection = true}>
                🔒 Cambiar Contraseña
              </button>
            {/if}
          </div>

          {#if showPasswordSection}
            <form on:submit|preventDefault={changePassword} class="pw-form">
              <div class="form-group">
                <label class="form-label" for="pw-current">Contraseña actual</label>
                <input id="pw-current" class="input" type="password" bind:value={currentPassword} required autocomplete="current-password" />
              </div>

              <div class="form-group">
                <label class="form-label" for="pw-new">Nueva contraseña</label>
                <input id="pw-new" class="input" type="password" bind:value={newPassword} required minlength="6" autocomplete="new-password" />
              </div>

              <div class="form-group">
                <label class="form-label" for="pw-confirm">Confirmar nueva contraseña</label>
                <input id="pw-confirm" class="input" type="password" bind:value={confirmPassword} required minlength="6" autocomplete="new-password" />
                {#if confirmPassword && newPassword !== confirmPassword}
                  <small class="text-danger">Las contraseñas no coinciden</small>
                {/if}
              </div>

              <div class="form-actions">
                <button type="button" class="btn btn-ghost" on:click={() => { showPasswordSection = false; currentPassword = ''; newPassword = ''; confirmPassword = ''; }}>
                  Cancelar
                </button>
                <button type="submit" class="btn btn-primary" disabled={changingPassword || !currentPassword || !newPassword || newPassword !== confirmPassword}>
                  {changingPassword ? 'Cambiando…' : 'Cambiar Contraseña'}
                </button>
              </div>
            </form>
          {:else}
            <p class="muted text-sm">Cambie su contraseña para mantener su cuenta segura.</p>
          {/if}
        </div>
      </div>

    </div>
  {/if}
</div>

<style>
.profile-page { max-width: 900px; }

.loading-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 60px 0;
  gap: 12px;
  color: var(--text-muted);
}

.profile-grid {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

/* Avatar / Info */
.profile-avatar {
  display: flex;
  align-items: center;
  gap: 16px;
  margin-bottom: 20px;
}
.avatar-circle {
  width: 64px;
  height: 64px;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--primary), var(--primary-dark));
  color: white;
  font-size: 1.75rem;
  font-weight: 800;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.avatar-name {
  font-size: 1.25rem;
  font-weight: 700;
  color: var(--text);
  margin: 0;
}
.avatar-username {
  font-size: .85rem;
  color: var(--text-muted);
  margin: 2px 0 0;
}
.role-tags {
  display: flex;
  gap: 6px;
  margin-top: 6px;
  flex-wrap: wrap;
}
.role-tag {
  font-size: .7rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .06em;
  padding: 2px 10px;
  border-radius: 99px;
  background: var(--primary-light);
  color: var(--primary-dark);
}

.profile-meta {
  display: flex;
  gap: 24px;
  padding-top: 16px;
  border-top: 1px solid var(--border);
  flex-wrap: wrap;
}
.meta-item {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.meta-label {
  font-size: .7rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .06em;
  color: var(--text-muted);
}
.meta-value {
  font-size: .875rem;
  color: var(--text);
}

/* Section Title */
.section-title {
  font-size: 1rem;
  font-weight: 700;
  color: var(--text);
  margin: 0 0 20px;
}

/* Form */
.form-group {
  margin-bottom: 16px;
}
.form-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 24px;
}
.input-readonly {
  background: var(--surface-2) !important;
  color: var(--text-muted) !important;
  cursor: not-allowed;
}
.text-danger {
  color: var(--danger);
  font-size: .8rem;
}

/* Password */
.pw-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 12px;
}
.pw-header .section-title { margin-bottom: 0; }
.pw-form { margin-top: 8px; }

/* Spinner */
.spinner {
  width: 32px;
  height: 32px;
  border: 3px solid var(--border);
  border-top-color: var(--primary);
  border-radius: 50%;
  animation: spin .7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
