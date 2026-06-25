<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';
  import Modal from '$lib/components/Modal.svelte';

  let roles = [];
  let loading = true;
  let showModal = false;
  let editRole = null;
  let submitting = false;
  let form = { role_name: '', description: '' };

  async function load() {
    loading = true;
    try {
      const res = await api.get('/api/admin/roles');
      roles = res?.data ?? res ?? [];
    } catch (e) {
      toasts.error(e.message || 'Failed to load roles');
    } finally {
      loading = false;
    }
  }

  function openCreate() {
    editRole = null;
    form = { role_name: '', description: '' };
    showModal = true;
  }

  function openEdit(r) {
    editRole = r;
    form = { role_name: r.role_name, description: r.description ?? '' };
    showModal = true;
  }

  async function handleSubmit() {
    submitting = true;
    try {
      if (editRole) {
        await api.put(`/api/admin/roles/${editRole.role_id}`, form);
        toasts.success('Role updated');
      } else {
        await api.post('/api/admin/roles', form);
        toasts.success('Role created');
      }
      showModal = false;
      await load();
    } catch (e) {
      toasts.error(e.message || 'Save failed');
    } finally {
      submitting = false;
    }
  }

  async function toggleStatus(r) {
    try {
      await api.patch(`/api/admin/roles/${r.role_id}/status`, { is_active: !r.is_active });
      toasts.success(`Role ${r.is_active ? 'deactivated' : 'activated'}`);
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
    <h2 class="page-title">Roles</h2>
    <p class="page-subtitle">Define access roles for system users</p>
  </div>
  <button class="btn btn-primary" on:click={openCreate}>＋ Add Role</button>
</div>

{#if loading}
  <div class="empty-state"><div class="spinner" /> Loading…</div>
{:else if roles.length === 0}
  <div class="empty-state">
    <span class="icon">🔑</span>
    <p>No roles defined yet.</p>
  </div>
{:else}
  <div class="card">
    <div class="table-wrap">
      <table>
        <thead>
          <tr><th>Role Name</th><th>Description</th><th>Status</th><th>Actions</th></tr>
        </thead>
        <tbody>
          {#each roles as r}
            <tr>
              <td><strong>{r.role_name}</strong></td>
              <td class="muted">{r.description ?? '—'}</td>
              <td>
                <span class="badge {r.is_active ? 'badge-success' : 'badge-danger'}">
                  {r.is_active ? 'Active' : 'Inactive'}
                </span>
              </td>
              <td>
                <div class="row-actions">
                  <button class="btn btn-ghost btn-sm" on:click={() => openEdit(r)}>Edit</button>
                  <button
                    class="btn btn-sm {r.is_active ? 'btn-warning' : 'btn-success'}"
                    on:click={() => toggleStatus(r)}
                  >
                    {r.is_active ? 'Deactivate' : 'Activate'}
                  </button>
                </div>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  </div>
{/if}

<Modal bind:open={showModal} title={editRole ? 'Edit Role' : 'Create Role'} on:close={() => showModal = false}>
  <form on:submit|preventDefault={handleSubmit} class="modal-form">
    <div class="form-group">
      <label class="form-label">Role Name</label>
      <input class="input" bind:value={form.role_name} required placeholder="e.g. Admin, Nurse" />
    </div>
    <div class="form-group">
      <label class="form-label">Description</label>
      <input class="input" bind:value={form.description} placeholder="What this role can do…" />
    </div>
    <div class="modal-footer">
      <button type="button" class="btn btn-ghost" on:click={() => showModal = false}>Cancel</button>
      <button type="submit" class="btn btn-primary" disabled={submitting}>
        {submitting ? 'Saving…' : editRole ? 'Update' : 'Create'}
      </button>
    </div>
  </form>
</Modal>

<style>
.back-link { display: inline-flex; align-items: center; gap: 4px; font-size: .8125rem; font-weight: 600; color: var(--text-muted); text-decoration: none; margin-bottom: 14px; transition: color .15s; }
.back-link:hover { color: var(--primary); }
.modal-form { display: flex; flex-direction: column; gap: 16px; }
.modal-footer { display: flex; justify-content: flex-end; gap: 8px; margin-top: 8px; }
.row-actions { display: flex; gap: 6px; }
.spinner {
  width: 24px; height: 24px;
  border: 3px solid var(--border);
  border-top-color: var(--primary);
  border-radius: 50%;
  animation: spin .7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
