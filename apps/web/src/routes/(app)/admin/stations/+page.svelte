<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';
  import Modal from '$lib/components/Modal.svelte';

  let stations = [];
  let users = [];
  let prefixes = [];   // active queue_settings
  let loading = true;

  // Station modal
  let showStationModal = false;
  let editStation = null;
  let submitting = false;
  let stationForm = { station_name: '', prefix: '' };

  // Station-users modal
  let showUsersModal = false;
  let activeStation = null;
  let stationUsers = [];
  let assignUserId = '';
  let assignRole = 'operator';

  async function load() {
    loading = true;
    try {
      const [s, u, qs] = await Promise.all([
        api.get('/api/admin/stations'),
        api.get('/api/admin/users'),
        api.get('/api/admin/queue-settings')   // active only (archived=false)
      ]);
      stations = s?.data ?? s ?? [];
      const allUsers = u?.data ?? u ?? [];
      // Solo usuarios activos y no archivados para el dropdown de asignación
      users = allUsers.filter(u => u.is_active && !u.is_archived);
      prefixes = qs?.data ?? qs ?? [];
    } catch (e) {
      toasts.error(e.message || 'Failed to load');
    } finally {
      loading = false;
    }
  }

  function openCreate() {
    editStation = null;
    stationForm = { station_name: '', prefix: '' };
    showStationModal = true;
  }

  function openEdit(s) {
    editStation = s;
    stationForm = { station_name: s.station_name, prefix: s.prefix ?? '' };
    showStationModal = true;
  }

  async function handleStationSubmit() {
    submitting = true;
    try {
      if (editStation) {
        await api.put(`/api/admin/stations/${editStation.station_id}`, stationForm);
        toasts.success('Station updated');
      } else {
        await api.post('/api/admin/stations', stationForm);
        toasts.success('Station created');
      }
      showStationModal = false;
      await load();
    } catch (e) {
      toasts.error(e.message || 'Save failed');
    } finally {
      submitting = false;
    }
  }

  async function toggleStatus(s) {
    try {
      await api.patch(`/api/admin/stations/${s.station_id}/status`, { is_active: !s.is_active });
      toasts.success(`Station ${s.is_active ? 'deactivated' : 'activated'}`);
      await load();
    } catch (e) {
      toasts.error(e.message);
    }
  }

  async function openStationUsers(s) {
    activeStation = s;
    stationUsers = [];
    assignUserId = users[0]?.user_id ?? '';
    assignRole = 'operator';
    try {
      const res = await api.get(`/api/admin/stations/${s.station_id}/users`);
      stationUsers = res?.data ?? res ?? [];
    } catch (e) {
      toasts.error(e.message);
    }
    showUsersModal = true;
  }

  async function assignUser() {
    if (!assignUserId) return;
    try {
      await api.post(`/api/admin/stations/${activeStation.station_id}/users`, {
        user_id: assignUserId,
        station_role: assignRole,
      });
      toasts.success('User assigned');
      const res = await api.get(`/api/admin/stations/${activeStation.station_id}/users`);
      stationUsers = res?.data ?? res ?? [];
    } catch (e) {
      toasts.error(e.message);
    }
  }

  async function removeStationUser(su) {
    try {
      await api.delete(`/api/admin/stations/${activeStation.station_id}/users/${su.user_id}`);
      toasts.success('User removed');
      stationUsers = stationUsers.filter((x) => x.user_id !== su.user_id);
    } catch (e) {
      toasts.error(e.message);
    }
  }

  // Computed: stations grouped by prefix
  $: groupedStations = stations.reduce((acc, s) => {
    const key = s.prefix || 'Unassigned';
    if (!acc[key]) acc[key] = [];
    acc[key].push(s);
    return acc;
  }, {});

  $: sortedGroups = Object.keys(groupedStations).sort();

  onMount(load);
</script>

<a href="/admin/settings" class="back-link">← Settings</a>

<div class="page-header">
  <div>
    <h2 class="page-title">Estaciones Disponibles</h2>
    <p class="page-subtitle">Configure los puntos físicos de atención (Consultorios, Ventanillas, etc.)</p>
  </div>
  <button class="btn btn-primary" on:click={openCreate}>＋ Nueva Estación</button>
</div>

{#if loading}
  <div class="empty-state"><div class="spinner" /> Cargando estaciones…</div>
{:else if stations.length === 0}
  <div class="empty-state">
    <span class="icon">🖥️</span>
    <p>No hay estaciones configuradas.</p>
  </div>
{:else}
  <div class="stations-container">
    {#each sortedGroups as groupPrefix}
      <div class="prefix-group">
        <div class="group-header">
          <span class="badge badge-purple">Área: {groupPrefix}</span>
          <span class="group-count">{groupedStations[groupPrefix].length} estaciones</span>
        </div>
        
        <div class="card">
          <div class="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Nombre de Estación</th>
                  <th>Código</th>
                  <th>Estado</th>
                  <th>Acciones</th>
                </tr>
              </thead>
              <tbody>
                {#each groupedStations[groupPrefix] as s}
                  <tr>
                    <td><strong>{s.station_name}</strong></td>
                    <td class="muted text-sm">{s.station_code}</td>
                    <td>
                      <span class="badge {s.is_active ? 'badge-success' : 'badge-danger'}">
                        {s.is_active ? 'Activa' : 'Inactiva'}
                      </span>
                    </td>
                    <td>
                      <div class="row-actions">
                        <button class="btn btn-ghost btn-sm" on:click={() => openEdit(s)}>Editar</button>
                        <button class="btn btn-ghost btn-sm" on:click={() => openStationUsers(s)}>👥 Operadores</button>
                        <button
                          class="btn btn-sm {s.is_active ? 'btn-warning' : 'btn-success'}"
                          on:click={() => toggleStatus(s)}
                        >
                          {s.is_active ? 'Desactivar' : 'Activar'}
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

<!-- Station modal -->
<Modal bind:open={showStationModal} title={editStation ? 'Edit Station' : 'Create Station'} on:close={() => showStationModal = false}>
  <form on:submit|preventDefault={handleStationSubmit} class="modal-form">
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Station Name</label>
        <input class="input" bind:value={stationForm.station_name} required placeholder="e.g. Window 1" />
      </div>
      <div class="form-group">
        <label class="form-label">Área / Prefix</label>
        <select class="input" bind:value={stationForm.prefix} required>
          <option value="" disabled>Selecciona un área…</option>
          {#each prefixes as qs}
            <option value={qs.prefix}>
              {qs.icon ? qs.icon + ' ' : ''}{qs.service_name || qs.prefix} ({qs.prefix})
            </option>
          {/each}
        </select>
      </div>
    </div>
    <div class="modal-footer">
      <button type="button" class="btn btn-ghost" on:click={() => showStationModal = false}>Cancel</button>
      <button type="submit" class="btn btn-primary" disabled={submitting}>
        {submitting ? 'Saving…' : editStation ? 'Update' : 'Create'}
      </button>
    </div>
  </form>
</Modal>

<!-- Station users modal -->
<Modal bind:open={showUsersModal} title="Station Users — {activeStation?.station_name ?? ''}" on:close={() => showUsersModal = false}>
  <div class="su-assign">
    <select class="input" bind:value={assignUserId}>
      {#each users as u}
        <option value={u.user_id}>{u.full_name ?? u.username}</option>
      {/each}
    </select>
    <select class="input select-sm" bind:value={assignRole}>
      <option value="operator">Operator</option>
      <option value="supervisor">Supervisor</option>
    </select>
    <button class="btn btn-primary" on:click={assignUser}>Assign</button>
  </div>

  {#if stationUsers.length > 0}
    <ul class="su-list">
      {#each stationUsers as su}
        <li class="su-item">
          <span>{su.full_name ?? su.username}</span>
          <span class="badge badge-purple">{su.station_role}</span>
          <button class="btn btn-danger btn-sm" on:click={() => removeStationUser(su)}>Remove</button>
        </li>
      {/each}
    </ul>
  {:else}
    <p class="muted text-sm" style="margin-top:12px">No users assigned.</p>
  {/if}
</Modal>

<style>
.back-link { display: inline-flex; align-items: center; gap: 4px; font-size: .8125rem; font-weight: 600; color: var(--text-muted); text-decoration: none; margin-bottom: 14px; transition: color .15s; }
.back-link:hover { color: var(--primary); }
.stations-container { display: flex; flex-direction: column; gap: 32px; }
.prefix-group { display: flex; flex-direction: column; gap: 12px; }
.group-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 4px;
}
.group-count {
  font-size: 0.85rem;
  color: var(--text-muted);
  font-weight: 500;
}
.modal-form { display: flex; flex-direction: column; gap: 16px; }
.form-row   { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.modal-footer { display: flex; justify-content: flex-end; gap: 8px; margin-top: 8px; }
.row-actions  { display: flex; gap: 6px; }
.su-assign { display: flex; gap: 8px; align-items: center; margin-bottom: 16px; }
.su-assign .input { flex: 1; }
.select-sm { max-width: 130px; }
.su-list { list-style: none; display: flex; flex-direction: column; gap: 6px; }
.su-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 8px 12px;
  background: var(--surface-2);
  border-radius: var(--radius-sm);
  font-size: .875rem;
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
