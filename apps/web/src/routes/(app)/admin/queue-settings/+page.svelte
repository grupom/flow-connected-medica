<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';
  import Modal from '$lib/components/Modal.svelte';

  let settings = [];
  let loading = true;

  // Modal State
  let showModal = false;
  let isEditing = false;
  let submitting = false;

  let form = {
    prefix: '',
    service_name: '',
    icon: '',
    mode: 'DAILY_RESET',
    min_number: 1,
    max_number: 99,
    max_active: null,
    allow_walkins: true,
    is_priority_for: null
  };

  // Non-archived, non-priority prefixes available as parent options
  $: priorityParentOptions = settings.filter(s => !s.archived && !s.is_priority_for);

  function openCreate() {
    isEditing = false;
    form = {
      prefix: '',
      service_name: '',
      icon: '',
      mode: 'DAILY_RESET',
      min_number: 1,
      max_number: 99,
      max_active: null,
      allow_walkins: true,
      is_priority_for: null
    };
    showModal = true;
  }

  function openEdit(s) {
    isEditing = true;
    form = {
      prefix:          s.prefix,
      service_name:    s.service_name || '',
      icon:            s.icon || '',
      mode:            s.mode,
      min_number:      s.min_number,
      max_number:      s.max_number,
      max_active:      s.max_active,
      allow_walkins:   s.allow_walkins,
      is_priority_for: s.is_priority_for || null
    };
    showModal = true;
  }

  async function handleSubmit() {
    submitting = true;
    try {
      const payload = {
        ...form,
        max_active:      form.max_active === '' || form.max_active === null ? null : parseInt(form.max_active, 10),
        is_priority_for: form.is_priority_for || null,
        // Priority prefixes cannot allow kiosk walkins — enforced also on API
        allow_walkins:   form.is_priority_for ? false : form.allow_walkins,
      };

      if (isEditing) {
        await api.put(`/api/admin/queue-settings/${form.prefix}`, payload);
        toasts.success('Settings updated');
      } else {
        await api.post('/api/admin/queue-settings', payload);
        toasts.success('Settings created');
      }
      showModal = false;
      await loadSettings();
    } catch (e) {
      toasts.error(e.message || 'Save failed');
    } finally {
      submitting = false;
    }
  }

  let showArchived = false;

  $: activeSettings   = settings.filter(s => !s.archived);
  $: archivedSettings = settings.filter(s =>  s.archived);

  async function loadSettings() {
    loading = true;
    try {
      const res = await api.get('/api/admin/queue-settings?include_archived=true');
      settings = res?.data ?? res ?? [];
    } catch (e) {
      toasts.error(e.message || 'Failed to load queue settings');
    } finally {
      loading = false;
    }
  }

  async function archiveSetting(prefix) {
    if (!confirm(`¿Archivar el prefijo '${prefix}'? Los tickets existentes no se verán afectados, pero no se podrán crear nuevos.`)) return;
    try {
      await api.patch(`/api/admin/queue-settings/${prefix}/archive`, {});
      toasts.success(`Prefijo '${prefix}' archivado.`);
      await loadSettings();
    } catch (e) {
      toasts.error(e.message || 'Error al archivar');
    }
  }

  async function restoreSetting(prefix) {
    try {
      await api.patch(`/api/admin/queue-settings/${prefix}/restore`, {});
      toasts.success(`Prefijo '${prefix}' restaurado.`);
      await loadSettings();
    } catch (e) {
      toasts.error(e.message || 'Error al restaurar');
    }
  }

  onMount(loadSettings);
</script>

<svelte:head>
  <title>Queue Settings — Admin</title>
</svelte:head>

<a href="/admin/settings" class="back-link">← Settings</a>

<div class="page-header">
  <div>
    <h2 class="page-title">Module Prefixes</h2>
    <p class="page-subtitle">Configure ticket generation rules per service prefix</p>
  </div>
  <button class="btn btn-primary" on:click={openCreate}>＋ Add Prefix Config</button>
</div>

{#if loading}
  <div class="empty-state"><div class="spinner" /> Loading…</div>
{:else}

  <!-- Active settings -->
  {#if activeSettings.length === 0}
    <div class="empty-state">
      <span class="icon">⚙️</span>
      <p>No queue settings configured yet.</p>
    </div>
  {:else}
    <div class="card">
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Prefix</th>
              <th>Service Name</th>
              <th>Icon</th>
              <th>Mode</th>
              <th>Range</th>
              <th>Max Active</th>
              <th>Walk-ins</th>
              <th>Priority de</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {#each activeSettings as s}
              <tr class="{s.is_priority_for ? 'priority-row' : ''}">
                <td>
                  <div class="prefix-cell">
                    {#if s.is_priority_for}
                      <span class="priority-badge">⚡</span>
                    {/if}
                    <span class="badge {s.is_priority_for ? 'badge-priority' : 'badge-purple'}" style="font-size: 1rem">
                      {s.prefix}
                    </span>
                  </div>
                </td>
                <td><strong>{s.service_name || '--'}</strong></td>
                <td style="font-size: 1.5rem">{s.icon || ''}</td>
                <td>
                  <span class="badge {s.mode === 'DAILY_RESET' ? 'badge-primary' : 'badge-warning'}">
                    {s.mode}
                  </span>
                </td>
                <td class="muted">{s.min_number} — {s.max_number}</td>
                <td class="muted">{s.max_active ?? 'Unlimited'}</td>
                <td>
                  <span class="badge {s.allow_walkins ? 'badge-success' : 'badge-gray'}">
                    {s.allow_walkins ? 'Yes' : 'No'}
                  </span>
                </td>
                <td>
                  {#if s.is_priority_for}
                    <span class="badge badge-priority">{s.is_priority_for}</span>
                  {:else}
                    <span class="muted">—</span>
                  {/if}
                </td>
                <td>
                  <div class="row-actions">
                    <button class="btn btn-ghost btn-sm" on:click={() => openEdit(s)}>Edit</button>
                    <button class="btn btn-warning btn-sm" on:click={() => archiveSetting(s.prefix)}>Archive</button>
                  </div>
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </div>
  {/if}

  <!-- Archived settings toggle -->
  {#if archivedSettings.length > 0}
    <div class="archived-header">
      <button class="btn btn-ghost btn-sm" on:click={() => showArchived = !showArchived}>
        {showArchived ? '▲' : '▼'} Archivados ({archivedSettings.length})
      </button>
    </div>

    {#if showArchived}
      <div class="card archived-card">
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Prefix</th>
                <th>Service Name</th>
                <th>Icon</th>
                <th>Mode</th>
                <th>Range</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {#each archivedSettings as s}
                <tr class="archived-row">
                  <td><span class="badge badge-gray" style="font-size: 1rem">{s.prefix}</span></td>
                  <td class="muted">{s.service_name || '--'}</td>
                  <td style="font-size: 1.5rem; opacity: 0.5">{s.icon || ''}</td>
                  <td><span class="badge badge-gray">{s.mode}</span></td>
                  <td class="muted">{s.min_number} — {s.max_number}</td>
                  <td>
                    <button class="btn btn-ghost btn-sm" on:click={() => restoreSetting(s.prefix)}>Restaurar</button>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      </div>
    {/if}
  {/if}

{/if}

<Modal bind:open={showModal} title={isEditing ? 'Edit Queue Setting' : 'Add Queue Setting'} on:close={() => showModal = false}>
  <form on:submit|preventDefault={handleSubmit} class="modal-form">
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Prefix <em>(1-2 chars)</em></label>
        <input
          class="input"
          bind:value={form.prefix}
          required
          maxlength="2"
          placeholder="e.g. C, PD"
          disabled={isEditing}
          style="text-transform: uppercase"
          on:input={e => form.prefix = e.target.value.toUpperCase()}
        />
      </div>
      <div class="form-group">
        <label class="form-label">Service Name</label>
        <input class="input" bind:value={form.service_name} placeholder="e.g. Consultorio" required />
      </div>
    </div>

    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Icon (Emoji)</label>
        <input class="input" bind:value={form.icon} placeholder="🩺" />
      </div>
      <div class="form-group">
        <label class="form-label">Reset Mode</label>
        <select class="input" bind:value={form.mode}>
          <option value="DAILY_RESET">Daily Reset (1...99)</option>
          <option value="GLOBAL">Global (Continuous)</option>
        </select>
      </div>
    </div>

    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Min Number</label>
        <input class="input" type="number" min="1" bind:value={form.min_number} required />
      </div>
      <div class="form-group">
        <label class="form-label">Max Number <em>(máx 99)</em></label>
        <input class="input" type="number" min="1" max="99" bind:value={form.max_number} required />
      </div>
    </div>

    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Max Active Tickets (Optional)</label>
        <input class="input" type="number" min="1" bind:value={form.max_active} placeholder="No limit" />
        <span class="text-xs muted block mt-4">Max tickets waiting/serving at once.</span>
      </div>
      <div class="form-group" style="display:flex; flex-direction:column; justify-content:center;">
        <label class="form-label" style="display:flex; align-items:center; gap:8px; cursor:pointer; {form.is_priority_for ? 'opacity:0.4;pointer-events:none' : ''}">
          <input type="checkbox" bind:checked={form.allow_walkins} disabled={!!form.is_priority_for} />
          Allow Kiosk Walk-ins
        </label>
        <span class="text-xs muted mt-4">
          {form.is_priority_for ? 'Deshabilitado — prefijos priority solo se emiten por Recepción.' : 'If unchecked, requires check-in/appointments.'}
        </span>
      </div>
    </div>

    <!-- Priority queue config -->
    <div class="form-group priority-section">
      <label class="form-label">⚡ Es prefijo de Prioridad para</label>
      <select class="input" bind:value={form.is_priority_for}
              on:change={() => { if (form.is_priority_for) form.allow_walkins = false; }}>
        <option value={null}>— Ninguno (prefijo regular) —</option>
        {#each priorityParentOptions.filter(p => p.prefix !== form.prefix) as parent}
          <option value={parent.prefix}>{parent.prefix} — {parent.service_name}</option>
        {/each}
      </select>
      {#if form.is_priority_for}
        <span class="text-xs priority-hint mt-4 block">
          ⚡ Tickets de este prefijo se llaman antes que los de <strong>{form.is_priority_for}</strong>.
          Solo se generan desde Recepción.
        </span>
      {:else}
        <span class="text-xs muted mt-4 block">
          Selecciona un prefijo padre si este es un carril de prioridad (embarazadas, adultos mayores, etc.)
        </span>
      {/if}
    </div>

    <div class="modal-footer">
      <button type="button" class="btn btn-ghost" on:click={() => showModal = false}>Cancel</button>
      <button type="submit" class="btn btn-primary" disabled={submitting}>
        {submitting ? 'Saving…' : isEditing ? 'Update Settings' : 'Create Settings'}
      </button>
    </div>
  </form>
</Modal>

<style>
.back-link { display: inline-flex; align-items: center; gap: 4px; font-size: .8125rem; font-weight: 600; color: var(--text-muted); text-decoration: none; margin-bottom: 14px; transition: color .15s; }
.back-link:hover { color: var(--primary); }
.modal-form { display: flex; flex-direction: column; gap: 16px; }
.form-row { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.modal-footer { display: flex; justify-content: flex-end; gap: 8px; margin-top: 16px; }
.row-actions { display: flex; gap: 6px; }
.mt-4 { margin-top: 4px; }
.block { display: block; }
.spinner {
  width: 24px; height: 24px;
  border: 3px solid var(--border);
  border-top-color: var(--primary);
  border-radius: 50%;
  animation: spin .7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

/* Priority UI */
.prefix-cell { display: flex; align-items: center; gap: 6px; }
.priority-badge { font-size: 0.85rem; }
.priority-row { background: #fffbeb; }
:global(.badge-priority) {
  background: #fef3c7;
  color: #92400e;
  font-weight: 700;
}
.priority-section {
  background: #fffbeb;
  border: 1px solid #fde68a;
  border-radius: 8px;
  padding: 12px 14px;
}
.priority-hint { color: #92400e; font-weight: 600; }

/* Archive UI */
.archived-header {
  margin-top: 24px;
  display: flex;
  align-items: center;
}
.archived-card {
  opacity: 0.75;
  border-style: dashed;
}
.archived-row td { color: var(--text-muted); }

/* Warning button */
:global(.btn-warning) {
  background: var(--warning, #f59e0b);
  color: #fff;
  border: none;
}
:global(.btn-warning:hover) {
  opacity: 0.85;
}
</style>
