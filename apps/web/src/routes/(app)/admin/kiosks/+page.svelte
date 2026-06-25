<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';
  import Modal from '$lib/components/Modal.svelte';

  let kiosks = [];
  let users = [];
  let queueSettings = [];
  let loading = true;

  // Kiosk modal
  let showKioskModal = false;
  let editKiosk = null;
  let submitting = false;
  let kioskForm = { kiosk_name: '', kiosk_code: '', user_id: '', location_desc: '' };

  // Queues modal
  let showQueuesModal = false;
  let activeKiosk = null;
  let selectedQueues = [];
  let savingQueues = false;

  async function load() {
    loading = true;
    try {
      const [k, u, q] = await Promise.all([
        api.get('/api/admin/kiosks'), 
        api.get('/api/admin/users'),
        api.get('/api/admin/queue-settings')
      ]);
      kiosks = k?.data ?? k ?? [];
      const allUsers = u?.data ?? u ?? [];
      // Solo usuarios activos y no archivados para el dropdown de asignación
      users = allUsers.filter(u => u.is_active && !u.is_archived);
      queueSettings = q?.data ?? q ?? [];
    } catch (e) {
      toasts.error(e.message || 'Failed to load data');
    } finally {
      loading = false;
    }
  }

  function openCreate() {
    editKiosk = null;
    kioskForm = { kiosk_name: '', kiosk_code: '', user_id: '', location_desc: '' };
    showKioskModal = true;
  }

  function openEdit(k) {
    editKiosk = k;
    kioskForm = { 
        kiosk_name: k.kiosk_name, 
        kiosk_code: k.kiosk_code, 
        user_id: k.user_id, 
        location_desc: k.location_desc ?? '' 
    };
    showKioskModal = true;
  }

  async function handleKioskSubmit() {
    submitting = true;
    try {
      if (editKiosk) {
        await api.put(`/api/admin/kiosks/${editKiosk.kiosk_id}`, kioskForm);
        toasts.success('Kiosco actualizado exitosamente');
      } else {
        await api.post('/api/admin/kiosks', kioskForm);
        toasts.success('Kiosco creado exitosamente');
      }
      showKioskModal = false;
      await load();
    } catch (e) {
      toasts.error(e.message || 'Error al guardar');
    } finally {
      submitting = false;
    }
  }

  async function toggleStatus(k) {
    try {
      await api.patch(`/api/admin/kiosks/${k.kiosk_id}/status`, { is_active: !k.is_active });
      toasts.success(`Kiosco ${k.is_active ? 'desactivado' : 'activado'}`);
      await load();
    } catch (e) {
      toasts.error(e.message);
    }
  }

  async function openKioskQueues(k) {
    activeKiosk = k;
    selectedQueues = [];
    showQueuesModal = true;
    
    try {
      const res = await api.get(`/api/admin/kiosks/${k.kiosk_id}`);
      const allowed = res.data.queues || [];
      selectedQueues = allowed.map(q => q.prefix);
    } catch (e) {
      toasts.error(e.message || 'Error al cargar colas del kiosco');
    }
  }

  async function saveQueues() {
    savingQueues = true;
    try {
      await api.put(`/api/admin/kiosks/${activeKiosk.kiosk_id}/queues`, {
        queues: selectedQueues
      });
      toasts.success('Áreas de servicio actualizadas');
      showQueuesModal = false;
    } catch (e) {
      toasts.error(e.message || 'Error al guardar áreas de servicio');
    } finally {
      savingQueues = false;
    }
  }

  function toggleQueue(prefix) {
    if (selectedQueues.includes(prefix)) {
      selectedQueues = selectedQueues.filter(p => p !== prefix);
    } else {
      selectedQueues = [...selectedQueues, prefix];
    }
  }

  onMount(load);
</script>

<a href="/admin/settings" class="back-link">← Settings</a>

<div class="page-header">
  <div>
    <h2 class="page-title">Gestión de Kioscos</h2>
    <p class="page-subtitle">Configure los terminales de autogestión y sus áreas permitidas</p>
  </div>
  <button class="btn btn-primary" on:click={openCreate}>＋ Nuevo Kiosco</button>
</div>

{#if loading}
  <div class="empty-state"><div class="spinner"></div> Cargando kioscos…</div>
{:else if kiosks.length === 0}
  <div class="empty-state">
    <span class="icon">🎟️</span>
    <p>No hay kioscos configurados.</p>
  </div>
{:else}
  <div class="kiosks-container">
    <div class="card">
        <div class="table-wrap">
        <table>
            <thead>
            <tr>
                <th>Nombre</th>
                <th>Código / ID</th>
                <th>Usuario Asignado</th>
                <th>Ubicación</th>
                <th>Estado</th>
                <th>Acciones</th>
            </tr>
            </thead>
            <tbody>
            {#each kiosks as k}
                <tr>
                <td><strong>{k.kiosk_name}</strong></td>
                <td class="muted text-sm">{k.kiosk_code}</td>
                <td>
                    {#if k.linked_user}
                        <span class="badge badge-purple">@{k.linked_user}</span>
                    {:else}
                        <span class="muted text-sm">-</span>
                    {/if}
                </td>
                <td class="muted text-sm">{k.location_desc || '-'}</td>
                <td>
                    <span class="badge {k.is_active ? 'badge-success' : 'badge-danger'}">
                    {k.is_active ? 'Activo' : 'Inactivo'}
                    </span>
                </td>
                <td>
                    <div class="row-actions">
                    <button class="btn btn-ghost btn-sm" on:click={() => openEdit(k)}>Editar</button>
                    <button class="btn btn-ghost btn-sm" on:click={() => openKioskQueues(k)}>📋 Áreas</button>
                    <button
                        class="btn btn-sm {k.is_active ? 'btn-warning' : 'btn-success'}"
                        on:click={() => toggleStatus(k)}
                    >
                        {k.is_active ? 'Inactivar' : 'Activar'}
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
{/if}

<!-- Kiosk Form Modal -->
<Modal bind:open={showKioskModal} title={editKiosk ? 'Editar Kiosco' : 'Crear Kiosco'} on:close={() => showKioskModal = false}>
  <form on:submit|preventDefault={handleKioskSubmit} class="modal-form">
    <div class="form-row">
      <div class="form-group">
        <label class="form-label" for="kiosk_name">Nombre de Kiosco</label>
        <input id="kiosk_name" class="input" bind:value={kioskForm.kiosk_name} required placeholder="Ej. Kiosco Principal lobby" />
      </div>
      <div class="form-group">
        <label class="form-label" for="kiosk_code">Código</label>
        <input id="kiosk_code" class="input" bind:value={kioskForm.kiosk_code} required placeholder="KIOSK_01" style="text-transform:uppercase" disabled={editKiosk} />
      </div>
    </div>
    
    <div class="form-group">
      <label class="form-label" for="user_id">Usuario de Sistema Asociado</label>
      <select id="user_id" class="input" bind:value={kioskForm.user_id} required>
        <option value="" disabled selected>Seleccione un usuario...</option>
        {#each users as u}
          <option value={u.user_id}>{u.full_name ?? u.username} ({u.username})</option>
        {/each}
      </select>
      <p class="text-sm muted" style="margin-top: 4px;">Este es el usuario con el que el dispositivo de kiosco iniciará sesión.</p>
    </div>

    <div class="form-group">
      <label class="form-label" for="location_desc">Ubicación (Opcional)</label>
      <input id="location_desc" class="input" bind:value={kioskForm.location_desc} placeholder="Ej. Primer piso, junto a recepción" />
    </div>

    <div class="modal-footer">
      <button type="button" class="btn btn-ghost" on:click={() => showKioskModal = false}>Cancelar</button>
      <button type="submit" class="btn btn-primary" disabled={submitting}>
        {submitting ? 'Guardando…' : editKiosk ? 'Actualizar' : 'Crear'}
      </button>
    </div>
  </form>
</Modal>

<!-- Kiosk Queues Modal -->
<Modal bind:open={showQueuesModal} title="Áreas Permitidas — {activeKiosk?.kiosk_name ?? ''}" on:close={() => showQueuesModal = false}>
  <p class="muted text-sm" style="margin-bottom: 24px;">
    Seleccione las áreas de servicio (colas) para las cuales este kiosco podrá emitir tickets.
  </p>

  <div class="queues-list">
    {#each queueSettings as qs}
      <label class="queue-checkbox-item">
        <input 
          type="checkbox" 
          checked={selectedQueues.includes(qs.prefix)} 
          on:change={() => toggleQueue(qs.prefix)} 
        />
        <div class="queue-info">
          <span class="queue-prefix badge badge-purple">{qs.prefix}</span>
          <span class="queue-name">{qs.service_name || `Área ${qs.prefix}`}</span>
        </div>
      </label>
    {/each}
    {#if queueSettings.length === 0}
      <p class="muted text-sm">No hay áreas de servicio configuradas en el sistema.</p>
    {/if}
  </div>

  <div class="modal-footer" style="margin-top: 24px;">
    <button type="button" class="btn btn-ghost" on:click={() => showQueuesModal = false}>Cancelar</button>
    <button type="button" class="btn btn-primary" on:click={saveQueues} disabled={savingQueues}>
      {savingQueues ? 'Guardando…' : 'Guardar Áreas'}
    </button>
  </div>
</Modal>

<style>
.back-link { display: inline-flex; align-items: center; gap: 4px; font-size: .8125rem; font-weight: 600; color: var(--text-muted); text-decoration: none; margin-bottom: 14px; transition: color .15s; }
.back-link:hover { color: var(--primary); }
.kiosks-container { display: flex; flex-direction: column; gap: 32px; }
.modal-form { display: flex; flex-direction: column; gap: 16px; }
.form-row   { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.modal-footer { display: flex; justify-content: flex-end; gap: 8px; margin-top: 16px; }
.row-actions  { display: flex; gap: 6px; }

.queues-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
  max-height: 400px;
  overflow-y: auto;
}

.queue-checkbox-item {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 12px 16px;
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  cursor: pointer;
  transition: border-color 0.2s, background 0.2s;
}

.queue-checkbox-item:hover {
  border-color: var(--primary);
  background: var(--surface);
}

.queue-checkbox-item input[type="checkbox"] {
  width: 18px;
  height: 18px;
  cursor: pointer;
}

.queue-info {
  display: flex;
  align-items: center;
  gap: 12px;
}

.queue-name {
  font-weight: 500;
  color: var(--text);
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
