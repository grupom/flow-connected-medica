<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';
  import Modal from '$lib/components/Modal.svelte';

  let modules = [];
  let prefixes = [];   // active queue_settings
  let loading = true;
  let showModal = false;
  let editMod = null;
  let submitting = false;
  let form = { module_name: '', prefix: '', display_order: 1 };

  async function load() {
    loading = true;
    try {
      const [res, qs] = await Promise.all([
        api.get('/api/admin/modules'),
        api.get('/api/admin/queue-settings')   // active only
      ]);
      modules  = res?.data ?? res ?? [];
      prefixes = qs?.data  ?? qs  ?? [];
    } catch (e) {
      toasts.error(e.message || 'Failed to load modules');
    } finally {
      loading = false;
    }
  }

  function openCreate() {
    editMod = null;
    form = { module_name: '', prefix: '', display_order: 1 };
    showModal = true;
  }

  function openEdit(m) {
    editMod = m;
    form = { module_name: m.module_name, prefix: m.prefix ?? '', display_order: m.display_order ?? 1 };
    showModal = true;
  }

  async function handleSubmit() {
    submitting = true;
    try {
      if (editMod) {
        await api.put(`/api/admin/modules/${editMod.module_id}`, form);
        toasts.success('Module updated');
      } else {
        await api.post('/api/admin/modules', form);
        toasts.success('Module created');
      }
      showModal = false;
      await load();
    } catch (e) {
      toasts.error(e.message || 'Save failed');
    } finally {
      submitting = false;
    }
  }

  async function toggleStatus(m) {
    try {
      await api.patch(`/api/admin/modules/${m.module_id}/status`, { is_active: !m.is_active });
      toasts.success(`Module ${m.is_active ? 'deactivated' : 'activated'}`);
      await load();
    } catch (e) {
      toasts.error(e.message);
    }
  }

  // Computed: modules grouped by prefix
  $: groupedModules = modules.reduce((acc, m) => {
    const key = m.prefix || 'Sin Prefijo';
    if (!acc[key]) acc[key] = [];
    acc[key].push(m);
    return acc;
  }, {});

  $: sortedGroups = Object.keys(groupedModules).sort();

  onMount(load);
</script>

<a href="/admin/settings" class="back-link">← Settings</a>

<div class="page-header">
  <div>
    <h2 class="page-title">Módulos Administrativos</h2>
    <p class="page-subtitle">Gestión de departamentos y categorías de servicios</p>
  </div>
  <button class="btn btn-primary" on:click={openCreate}>＋ Nuevo Módulo</button>
</div>

{#if loading}
  <div class="empty-state"><div class="spinner" /> Cargando módulos…</div>
{:else if modules.length === 0}
  <div class="empty-state">
    <span class="icon">🧩</span>
    <p>No hay módulos configurados.</p>
  </div>
{:else}
  <div class="group-container">
    {#each sortedGroups as groupPrefix}
       <div class="prefix-group">
         <div class="group-header">
           <span class="badge badge-purple">Prefijo: {groupPrefix}</span>
         </div>
         
         <div class="card">
            <div class="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Nombre de Módulo</th>
                    <th>Estado</th>
                    <th>Orden</th>
                    <th>Acciones</th>
                  </tr>
                </thead>
                <tbody>
                  {#each groupedModules[groupPrefix] as m}
                    <tr>
                      <td><strong>{m.module_name}</strong></td>
                      <td>
                        <span class="badge {m.is_active ? 'badge-success' : 'badge-danger'}">
                          {m.is_active ? 'Activo' : 'Inactivo'}
                        </span>
                      </td>
                      <td class="muted">{m.display_order}</td>
                      <td>
                        <div class="row-actions">
                          <button class="btn btn-ghost btn-sm" on:click={() => openEdit(m)}>Editar</button>
                          <button
                            class="btn btn-sm {m.is_active ? 'btn-warning' : 'btn-success'}"
                            on:click={() => toggleStatus(m)}
                          >
                            {m.is_active ? 'Desactivar' : 'Activar'}
                          </button>
                        </div>
                      </td>
                    </tr>
                  {/each}
                </tbody>
              </table>
            </div>
         </div>
       </div>
    {/each}
  </div>
{/if}

<Modal bind:open={showModal} title={editMod ? 'Edit Module' : 'Create Module'} on:close={() => showModal = false}>
  <form on:submit|preventDefault={handleSubmit} class="modal-form">
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Module Name</label>
        <input class="input" bind:value={form.module_name} required placeholder="e.g. Consultorio 3" />
      </div>
      <div class="form-group">
        <label class="form-label">Área / Prefix</label>
        <select class="input" bind:value={form.prefix} required>
          <option value="" disabled>Selecciona un área…</option>
          {#each prefixes as qs}
            <option value={qs.prefix}>
              {qs.icon ? qs.icon + ' ' : ''}{qs.service_name || qs.prefix} ({qs.prefix})
            </option>
          {/each}
        </select>
      </div>
    </div>
    <div class="form-group">
      <label class="form-label">Display Order</label>
      <input class="input" type="number" min="1" bind:value={form.display_order} placeholder="1" />
    </div>
    <div class="modal-footer">
      <button type="button" class="btn btn-ghost" on:click={() => showModal = false}>Cancel</button>
      <button type="submit" class="btn btn-primary" disabled={submitting}>
        {submitting ? 'Saving…' : editMod ? 'Update' : 'Create'}
      </button>
    </div>
  </form>
</Modal>

<style>
.back-link { display: inline-flex; align-items: center; gap: 4px; font-size: .8125rem; font-weight: 600; color: var(--text-muted); text-decoration: none; margin-bottom: 14px; transition: color .15s; }
.back-link:hover { color: var(--primary); }
.group-container { display: flex; flex-direction: column; gap: 32px; }
.prefix-group { display: flex; flex-direction: column; gap: 12px; }
.group-header { padding: 0 4px; }
.modal-form { display: flex; flex-direction: column; gap: 16px; }
.form-row { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
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
