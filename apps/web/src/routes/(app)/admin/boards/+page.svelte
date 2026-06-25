<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';
  import Modal from '$lib/components/Modal.svelte';
  import { DingPlayer, DING_OPTIONS } from '$lib/audio/DingPlayer.js';

  let boards = [];
  let stations = [];
  let loading = true;

  // Board modal
  let showBoardModal = false;
  let editBoard = null;
  let submitting = false;
  let boardForm = { board_name: '', board_code: '', description: '' };

  // Board-stations modal
  let showStationsModal = false;
  let activeBoard = null;
  let boardStations = [];
  let assignStationId = '';
  let displayOrder = 1;

  async function load() {
    loading = true;
    try {
      const [b, s] = await Promise.all([api.get('/api/admin/boards'), api.get('/api/admin/stations')]);
      boards = b?.data ?? b ?? [];
      stations = s?.data ?? s ?? [];
    } catch (e) {
      toasts.error(e.message || 'Failed to load');
    } finally {
      loading = false;
    }
  }

  let previewingDing = false;

  function openCreate() {
    editBoard = null;
    boardForm = { board_name: '', board_code: '', description: '', voice_speed: 1.0, language: 'es', ding_sound: 'gentle' };
    showBoardModal = true;
  }

  function openEdit(b) {
    editBoard = b;
    boardForm = { board_name: b.board_name, board_code: b.board_code, description: b.description ?? '', voice_speed: b.voice_speed ?? 1.0, language: b.language ?? 'es', ding_sound: b.ding_sound ?? 'gentle' };
    showBoardModal = true;
  }

  async function previewDing() {
    previewingDing = true;
    await DingPlayer.play(boardForm.ding_sound || 'gentle');
    previewingDing = false;
  }

  async function handleBoardSubmit() {
    submitting = true;
    try {
      if (editBoard) {
        await api.put(`/api/admin/boards/${editBoard.board_id}`, boardForm);
        toasts.success('Board updated');
      } else {
        await api.post('/api/admin/boards', boardForm);
        toasts.success('Board created');
      }
      showBoardModal = false;
      await load();
    } catch (e) {
      toasts.error(e.message || 'Save failed');
    } finally {
      submitting = false;
    }
  }

  async function deleteBoard(b) {
    if (!confirm(`Delete board "${b.board_name}"?`)) return;
    try {
      await api.delete(`/api/admin/boards/${b.board_id}`);
      toasts.success('Board deleted');
      await load();
    } catch (e) {
      toasts.error(e.message);
    }
  }

  async function openBoardStations(b) {
    activeBoard = b;
    boardStations = [];
    assignStationId = stations[0]?.station_id ?? '';
    displayOrder = 1;
    try {
      const res = await api.get(`/api/admin/boards/${b.board_id}/stations`);
      boardStations = res?.data ?? res ?? [];
    } catch (e) {
      toasts.error(e.message);
    }
    showStationsModal = true;
  }

  async function assignStation() {
    if (!assignStationId) return;
    try {
      await api.post(`/api/admin/boards/${activeBoard.board_id}/stations`, {
        station_id: assignStationId,
        display_order: Number(displayOrder),
      });
      toasts.success('Station added to board');
      const res = await api.get(`/api/admin/boards/${activeBoard.board_id}/stations`);
      boardStations = res?.data ?? res ?? [];
    } catch (e) {
      toasts.error(e.message);
    }
  }

  async function removeBoardStation(bs) {
    try {
      await api.delete(`/api/admin/boards/${activeBoard.board_id}/stations/${bs.station_id}`);
      toasts.success('Station removed');
      boardStations = boardStations.filter((x) => x.station_id !== bs.station_id);
    } catch (e) {
      toasts.error(e.message);
    }
  }

  onMount(load);
</script>

<div class="page-header">
  <div>
    <h2 class="page-title">Display Boards</h2>
    <p class="page-subtitle">Configure public display boards and their station assignments</p>
  </div>
  <button class="btn btn-primary" on:click={openCreate}>＋ Add Board</button>
</div>

{#if loading}
  <div class="empty-state"><div class="spinner" /> Loading…</div>
{:else if boards.length === 0}
  <div class="empty-state">
    <span class="icon">📺</span>
    <p>No boards configured. Create one to show a queue display.</p>
  </div>
{:else}
  <div class="card">
    <div class="table-wrap">
      <table>
        <thead>
          <tr><th>Board Name</th><th>Code</th><th>Description</th><th>Live URL</th><th>Actions</th></tr>
        </thead>
        <tbody>
          {#each boards as b}
            <tr>
              <td><strong>{b.board_name}</strong></td>
              <td><span class="badge badge-primary">{b.board_code}</span></td>
              <td class="muted">{b.description ?? '—'}</td>
              <td>
                <a href="/board/{b.board_code}" target="_blank" class="text-sm">
                  /board/{b.board_code} ↗
                </a>
              </td>
              <td>
                <div class="row-actions">
                  <button class="btn btn-ghost btn-sm" on:click={() => openEdit(b)}>Edit</button>
                  <button class="btn btn-ghost btn-sm" on:click={() => openBoardStations(b)}>🖥️ Stations</button>
                  <button class="btn btn-danger btn-sm" on:click={() => deleteBoard(b)}>Delete</button>
                </div>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  </div>
{/if}

<!-- Board modal -->
<Modal bind:open={showBoardModal} title={editBoard ? 'Edit Board' : 'Create Board'} on:close={() => showBoardModal = false}>
  <form on:submit|preventDefault={handleBoardSubmit} class="modal-form">
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Board Name</label>
        <input class="input" bind:value={boardForm.board_name} required placeholder="Main Hall Board" />
      </div>
      <div class="form-group">
        <label class="form-label">Board Code</label>
        <input class="input" bind:value={boardForm.board_code} required placeholder="MAIN" style="text-transform:uppercase" />
      </div>
    </div>
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Description</label>
        <input class="input" bind:value={boardForm.description} placeholder="Where is this board located?" />
      </div>
      <div class="form-group">
        <label class="form-label">Voice Speed</label>
        <select class="input" bind:value={boardForm.voice_speed}>
          <option value={1.0}>1x</option>
          <option value={1.25}>1.25x</option>
          <option value={1.5}>1.5x</option>
          <option value={1.75}>1.75x</option>
          <option value={2.0}>2x</option>
        </select>
      </div>
    </div>
    <div class="form-row">
      <div class="form-group">
        <label class="form-label">Sonido de Notificación</label>
        <select class="input" bind:value={boardForm.ding_sound}>
          {#each DING_OPTIONS as opt}
            <option value={opt.value}>{opt.label}</option>
          {/each}
        </select>
      </div>
      <div class="form-group ding-preview-group">
        <label class="form-label">&nbsp;</label>
        <button type="button" class="btn btn-ghost ding-preview-btn" on:click={previewDing} disabled={previewingDing}>
          {previewingDing ? '♪ Reproduciendo…' : '▶ Escuchar'}
        </button>
      </div>
    </div>
    <div class="modal-footer">
      <button type="button" class="btn btn-ghost" on:click={() => showBoardModal = false}>Cancel</button>
      <button type="submit" class="btn btn-primary" disabled={submitting}>
        {submitting ? 'Saving…' : editBoard ? 'Update' : 'Create'}
      </button>
    </div>
  </form>
</Modal>

<!-- Board stations modal -->
<Modal bind:open={showStationsModal} title="Stations on: {activeBoard?.board_name ?? ''}" on:close={() => showStationsModal = false}>
  <div class="su-assign">
    <select class="input" bind:value={assignStationId}>
      {#each stations as s}
        <option value={s.station_id}>{s.station_name}</option>
      {/each}
    </select>
    <input class="input select-sm" type="number" min="1" bind:value={displayOrder} placeholder="Order" />
    <button class="btn btn-primary" on:click={assignStation}>Add</button>
  </div>

  {#if boardStations.length > 0}
    <ul class="su-list">
      {#each boardStations.sort((a,b) => a.display_order - b.display_order) as bs}
        <li class="su-item">
          <span class="badge badge-gray">#{bs.display_order}</span>
          <span>{bs.station_name}</span>
          <button class="btn btn-danger btn-sm" on:click={() => removeBoardStation(bs)}>Remove</button>
        </li>
      {/each}
    </ul>
  {:else}
    <p class="muted text-sm" style="margin-top:12px">No stations on this board.</p>
  {/if}
</Modal>

<style>
.modal-form { display: flex; flex-direction: column; gap: 16px; }
.form-row   { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.modal-footer { display: flex; justify-content: flex-end; gap: 8px; margin-top: 8px; }
.ding-preview-group { display: flex; flex-direction: column; }
.ding-preview-btn { align-self: flex-start; margin-top: auto; }
.row-actions  { display: flex; gap: 6px; }
.su-assign { display: flex; gap: 8px; align-items: center; margin-bottom: 16px; }
.su-assign .input { flex: 1; }
.select-sm { max-width: 90px !important; flex: none !important; }
.su-list { list-style: none; display: flex; flex-direction: column; gap: 6px; }
.su-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 12px;
  background: var(--surface-2);
  border-radius: var(--radius-sm);
  font-size: .875rem;
}
.su-item span:nth-child(2) { flex: 1; font-weight: 500; }
.spinner {
  width: 24px; height: 24px;
  border: 3px solid var(--border);
  border-top-color: var(--primary);
  border-radius: 50%;
  animation: spin .7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
