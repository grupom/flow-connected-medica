<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';
  import Modal from '$lib/components/Modal.svelte';

  let users = [];
  let roles = [];
  let loading = true;

  // Modal state
  let showModal = false;
  let editUser = null;  // null = create mode
  let submitting = false;
  let statusFilter = 'DEFAULT'; // DEFAULT, ALL, ACTIVE, INACTIVE, ARCHIVED

  let form = { username: '', full_name: '', email: '', password: '', role_id: '' };
  
  $: filteredUsers = users.filter(u => {
    if (statusFilter === 'DEFAULT') return u.status_code !== 'ARCHIVED';
    if (statusFilter === 'ALL') return true;
    return u.status_code === statusFilter;
  });

  function getStatusBadge(code) {
    if (code === 'ACTIVE') return 'badge-success';
    if (code === 'INACTIVE') return 'badge-warning';
    if (code === 'ARCHIVED') return 'badge-danger';
    return 'badge-primary';
  }

  async function load() {
    loading = true;
    try {
      const [u, r] = await Promise.all([api.get('/api/admin/users'), api.get('/api/admin/roles')]);
      users = u?.data ?? u ?? [];
      roles = r?.data ?? r ?? [];
    } catch (e) {
      toasts.error(e.message || 'Failed to load users');
    } finally {
      loading = false;
    }
  }

  function openCreate() {
    editUser = null;
    form = { username: '', full_name: '', email: '', password: '', role_id: roles[0]?.role_id ?? '' };
    showModal = true;
  }

  function openEdit(u) {
    editUser = u;
    // v_users returns display_name and a roles JSONB array
    const assignedRoleId = u.roles?.[0]?.role_id || '';
    form = { username: u.username, full_name: u.display_name ?? '', email: u.email ?? '', password: '', role_id: assignedRoleId };
    showModal = true;
  }

  async function handleSubmit() {
    submitting = true;
    try {
      if (editUser) {
        await api.put(`/api/admin/users/${editUser.user_id}`, {
          full_name: form.full_name,
          email: form.email,
        });
        if (form.password) {
          await api.patch(`/api/admin/users/${editUser.user_id}/password`, { password: form.password });
        }
        toasts.success('User updated');
      } else {
        await api.post('/api/admin/users', form);
        toasts.success('User created');
      }
      showModal = false;
      await load();
    } catch (e) {
      toasts.error(e.message || 'Save failed');
    } finally {
      submitting = false;
    }
  }

  async function changeStatus(u, newStatus) {
    if (newStatus === 'ARCHIVED' && !confirm('¿Seguro que desea archivar este usuario?')) return;
    try {
      await api.patch(`/api/admin/users/${u.user_id}/status`, { status_code: newStatus });
      toasts.success(`Estado del usuario actualizado a ${newStatus}`);
      await load();
    } catch (e) {
      toasts.error(e.message);
    }
  }

  onMount(load);
</script>

<a href="/admin/settings" class="back-link">← Settings</a>

<div class="page-header">
  <div>
    <h2 class="page-title">Usuarios</h2>
    <p class="page-subtitle">Gestión de cuentas de sistema y asignación de roles</p>
  </div>
  <button class="btn btn-primary" on:click={openCreate}>＋ Nuevo Usuario</button>
</div>

<div class="filters-bar">
  <label class="form-label">Filtrar por Estado:</label>
  <select class="input" bind:value={statusFilter} style="max-width: 250px;">
    <option value="DEFAULT">Activos e Inactivos</option>
    <option value="ALL">Todos los Usuarios</option>
    <option value="ACTIVE">Activos (ACTIVE)</option>
    <option value="INACTIVE">Inactivos (INACTIVE)</option>
    <option value="ARCHIVED">Archivados (ARCHIVED)</option>
  </select>
</div>

{#if loading}
  <div class="empty-state"><div class="spinner" /> Loading…</div>
{:else if users.length === 0}
  <div class="empty-state">
    <span class="icon">👥</span>
    <p>No users found. Create your first user above.</p>
  </div>
{:else}
  <div class="card">
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Name</th>
            <th>Username</th>
            <th>Email</th>
            <th>Role</th>
            <th>Status</th>
            <th>Last Login</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {#each filteredUsers as u}
            <tr class:archived-row={u.status_code === 'ARCHIVED'}>
              <td><strong>{u.display_name ?? u.username}</strong></td>
              <td class="muted">{u.username}</td>
              <td class="muted">{u.email ?? '—'}</td>
              <td>
                {#if u.roles && u.roles.length > 0}
                  {#each u.roles as role}
                    <span class="badge badge-purple">{role.role_name}</span>
                  {/each}
                {:else}
                  <span class="muted">—</span>
                {/if}
              </td>
              <td>
                <span class="badge {getStatusBadge(u.status_code)}">
                  {u.status_name}
                </span>
                {#if u.is_active !== undefined && u.status_code !== (u.is_active ? 'ACTIVE' : 'INACTIVE')}
                   <small class="muted" style="display:block;font-size:10px;">(Legacy: {u.is_active})</small>
                {/if}
              </td>
              <td class="muted text-sm">
                {u.last_login_at ? new Date(u.last_login_at).toLocaleString() : 'Nunca'}
              </td>
              <td>
                <div class="row-actions">
                  <button class="btn btn-ghost btn-sm" on:click={() => openEdit(u)}>Editar</button>
                  
                  {#if u.status_code === 'ACTIVE'}
                    <button class="btn btn-sm btn-warning" on:click={() => changeStatus(u, 'INACTIVE')}>Inactivar</button>
                    <button class="btn btn-sm btn-ghost" style="color:var(--danger)" on:click={() => changeStatus(u, 'ARCHIVED')}>Archivar</button>
                  {:else if u.status_code === 'INACTIVE'}
                    <button class="btn btn-sm btn-success" on:click={() => changeStatus(u, 'ACTIVE')}>Activar</button>
                    <button class="btn btn-sm btn-ghost" style="color:var(--danger)" on:click={() => changeStatus(u, 'ARCHIVED')}>Archivar</button>
                  {:else if u.status_code === 'ARCHIVED'}
                    <button class="btn btn-sm btn-ghost" on:click={() => changeStatus(u, 'INACTIVE')}>📍 Restaurar</button>
                  {/if}
                </div>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  </div>
{/if}

<Modal bind:open={showModal} title={editUser ? 'Edit User' : 'Create User'} on:close={() => showModal = false}>
  <form on:submit|preventDefault={handleSubmit} class="modal-form">
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Full Name</label>
        <input class="input" bind:value={form.full_name} required placeholder="Jane Doe" />
      </div>
      <div class="form-group">
        <label class="form-label">Email</label>
        <input class="input" type="email" bind:value={form.email} placeholder="jane@clinic.com" />
      </div>
    </div>
    {#if !editUser}
      <div class="form-row">
        <div class="form-group">
          <label class="form-label">Username</label>
          <input class="input" bind:value={form.username} required placeholder="jdoe" />
        </div>
        <div class="form-group">
          <label class="form-label">Password</label>
          <input class="input" type="password" bind:value={form.password} required minlength="6" placeholder="Min 6 chars" />
        </div>
      </div>
      <div class="form-group">
        <label class="form-label">Role</label>
        <select class="input" bind:value={form.role_id}>
          {#each roles as r}
            <option value={r.role_id}>{r.role_name}</option>
          {/each}
        </select>
      </div>
    {:else}
      <div class="form-group">
        <label class="form-label">New Password <span class="muted text-sm">(leave blank to keep)</span></label>
        <input class="input" type="password" bind:value={form.password} minlength="6" placeholder="New password…" />
      </div>
    {/if}
    <div class="modal-footer">
      <button type="button" class="btn btn-ghost" on:click={() => showModal = false}>Cancel</button>
      <button type="submit" class="btn btn-primary" disabled={submitting}>
        {submitting ? 'Saving…' : editUser ? 'Update User' : 'Create User'}
      </button>
    </div>
  </form>
</Modal>

<style>
.back-link { display: inline-flex; align-items: center; gap: 4px; font-size: .8125rem; font-weight: 600; color: var(--text-muted); text-decoration: none; margin-bottom: 14px; transition: color .15s; }
.back-link:hover { color: var(--primary); }
.form-row { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.modal-form { display: flex; flex-direction: column; gap: 16px; }
.modal-footer { display: flex; justify-content: flex-end; gap: 8px; margin-top: 8px; }
.row-actions { display: flex; gap: 6px; }

.filters-bar {
  display: flex;
  align-items: center;
  gap: 16px;
  background: var(--surface);
  padding: 16px;
  border-radius: var(--radius-lg);
  margin-bottom: 24px;
  border: 1px solid var(--border);
}
.filters-bar .form-label { margin: 0; font-weight: 600; }

.archived-row td {
  opacity: 0.6;
}

.spinner {
  width: 24px; height: 24px;
  border: 3px solid var(--border);
  border-top-color: var(--primary);
  border-radius: 50%;
  animation: spin .7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
