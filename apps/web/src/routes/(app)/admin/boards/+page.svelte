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

  // Ads / media modal
  let showMediaModal = false;
  let mediaBoard = null;
  let mediaMode = 'video'; // 'video' | 'image_sequence' — which uploader tab is shown
  let uploadingVideo = false;
  let videoUploadPct = 0;
  let pendingImages = [];   // [{ file, duration_seconds }] selected but not yet uploaded
  let uploadingImages = false;
  let imagesUploadPct = 0;
  let existingImages = [];  // working copy of mediaBoard.ad_images for reorder/duration edits
  let savingImageOrder = false;
  let rotationSeconds = 20;
  let cooldownSeconds = 8;
  let savingMediaSettings = false;

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

  function openMedia(b) {
    mediaBoard = b;
    mediaMode = b.ad_media_type === 'image_sequence' ? 'image_sequence' : 'video';
    pendingImages = [];
    existingImages = (b.ad_images ?? []).map((img) => ({ ...img }));
    rotationSeconds = b.ad_rotation_seconds ?? 20;
    cooldownSeconds = b.ad_interrupt_cooldown_seconds ?? 8;
    showMediaModal = true;
  }

  async function refreshMediaBoard() {
    await load();
    mediaBoard = boards.find((b) => b.board_id === mediaBoard.board_id) ?? mediaBoard;
    existingImages = (mediaBoard.ad_images ?? []).map((img) => ({ ...img }));
  }

  async function handleVideoSelect(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    uploadingVideo = true;
    videoUploadPct = 0;
    try {
      const fd = new FormData();
      fd.append('file', file);
      await api.upload(`/api/admin/boards/${mediaBoard.board_id}/media/video`, fd, {
        onProgress: (loaded, total) => { videoUploadPct = Math.round((loaded / total) * 100); },
      });
      toasts.success('Video de anuncio actualizado');
      await refreshMediaBoard();
    } catch (err) {
      toasts.error(err.message || 'Error al subir el video');
    } finally {
      uploadingVideo = false;
      e.target.value = '';
    }
  }

  function addPendingImages(e) {
    const files = Array.from(e.target.files ?? []);
    pendingImages = [...pendingImages, ...files.map((file) => ({ file, duration_seconds: 5 }))];
    e.target.value = '';
  }

  function movePendingImage(idx, dir) {
    const newIdx = idx + dir;
    if (newIdx < 0 || newIdx >= pendingImages.length) return;
    const copy = [...pendingImages];
    [copy[idx], copy[newIdx]] = [copy[newIdx], copy[idx]];
    pendingImages = copy;
  }

  function removePendingImage(idx) {
    pendingImages = pendingImages.filter((_, i) => i !== idx);
  }

  async function uploadImageSequence() {
    if (!pendingImages.length) return;
    uploadingImages = true;
    imagesUploadPct = 0;
    try {
      const fd = new FormData();
      pendingImages.forEach((p) => fd.append('file', p.file));
      fd.append('durations', JSON.stringify(pendingImages.map((p) => Number(p.duration_seconds) || 5)));
      await api.upload(`/api/admin/boards/${mediaBoard.board_id}/media/images`, fd, {
        onProgress: (loaded, total) => { imagesUploadPct = Math.round((loaded / total) * 100); },
      });
      toasts.success('Secuencia de imágenes actualizada');
      pendingImages = [];
      await refreshMediaBoard();
    } catch (err) {
      toasts.error(err.message || 'Error al subir las imágenes');
    } finally {
      uploadingImages = false;
    }
  }

  function moveExistingImage(idx, dir) {
    const newIdx = idx + dir;
    if (newIdx < 0 || newIdx >= existingImages.length) return;
    const copy = [...existingImages];
    [copy[idx], copy[newIdx]] = [copy[newIdx], copy[idx]];
    existingImages = copy;
  }

  async function saveImageOrder() {
    savingImageOrder = true;
    try {
      await api.patch(`/api/admin/boards/${mediaBoard.board_id}/media/images/order`, {
        images: existingImages.map(({ filename, duration_seconds }) => ({ filename, duration_seconds: Number(duration_seconds) || 5 })),
      });
      toasts.success('Secuencia actualizada');
      await refreshMediaBoard();
    } catch (err) {
      toasts.error(err.message || 'Error al guardar el orden');
    } finally {
      savingImageOrder = false;
    }
  }

  async function saveMediaSettings() {
    savingMediaSettings = true;
    try {
      await api.patch(`/api/admin/boards/${mediaBoard.board_id}/media/settings`, {
        ad_rotation_seconds: Number(rotationSeconds),
        ad_interrupt_cooldown_seconds: Number(cooldownSeconds),
      });
      toasts.success('Configuración de rotación guardada');
      await refreshMediaBoard();
    } catch (err) {
      toasts.error(err.message || 'Error al guardar');
    } finally {
      savingMediaSettings = false;
    }
  }

  async function removeAds() {
    if (!confirm('¿Quitar el anuncio activo de esta pizarra?')) return;
    try {
      await api.delete(`/api/admin/boards/${mediaBoard.board_id}/media`);
      toasts.success('Anuncio eliminado');
      await refreshMediaBoard();
    } catch (err) {
      toasts.error(err.message || 'Error al eliminar');
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
                  <button class="btn btn-ghost btn-sm" on:click={() => openMedia(b)}>
                    🎬 Ads{b.ad_media_type && b.ad_media_type !== 'none' ? ' ✓' : ''}
                  </button>
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

<!-- Ads / media modal -->
<Modal bind:open={showMediaModal} title="Anuncios: {mediaBoard?.board_name ?? ''}" on:close={() => showMediaModal = false}>
  <div class="media-mode-toggle">
    <button type="button" class="btn btn-sm {mediaMode === 'video' ? 'btn-primary' : 'btn-ghost'}" on:click={() => mediaMode = 'video'}>🎬 Video</button>
    <button type="button" class="btn btn-sm {mediaMode === 'image_sequence' ? 'btn-primary' : 'btn-ghost'}" on:click={() => mediaMode = 'image_sequence'}>🖼️ Secuencia de imágenes</button>
  </div>

  {#if mediaMode === 'video'}
    <div class="media-section">
      {#if mediaBoard?.ad_media_type === 'video' && mediaBoard?.ad_video_url}
        <video src={mediaBoard.ad_video_url} controls class="media-preview-video">
          <track kind="captions" />
        </video>
      {:else}
        <p class="muted text-sm">Esta pizarra no tiene un video activo.</p>
      {/if}
      <div class="form-group" style="margin-top:12px">
        <label class="form-label">Subir nuevo video (MP4, máx. 100MB) — reemplaza el actual</label>
        <input class="input" type="file" accept="video/mp4" on:change={handleVideoSelect} disabled={uploadingVideo} />
      </div>
      {#if uploadingVideo}
        <div class="upload-progress"><div class="upload-progress-bar" style="width:{videoUploadPct}%"></div></div>
        <p class="muted text-sm">Subiendo… {videoUploadPct}%</p>
      {/if}
    </div>
  {:else}
    <div class="media-section">
      {#if existingImages.length > 0}
        <p class="form-label">Secuencia activa</p>
        <ul class="image-seq-list">
          {#each existingImages as img, idx}
            <li class="image-seq-item">
              <img src={img.url} alt="" class="image-seq-thumb" />
              <input class="input select-sm" type="number" min="1" max="120" bind:value={img.duration_seconds} />
              <span class="muted text-sm">seg</span>
              <button type="button" class="btn btn-ghost btn-sm" on:click={() => moveExistingImage(idx, -1)} disabled={idx === 0}>↑</button>
              <button type="button" class="btn btn-ghost btn-sm" on:click={() => moveExistingImage(idx, 1)} disabled={idx === existingImages.length - 1}>↓</button>
            </li>
          {/each}
        </ul>
        <button type="button" class="btn btn-primary btn-sm" on:click={saveImageOrder} disabled={savingImageOrder}>
          {savingImageOrder ? 'Guardando…' : 'Guardar orden/duración'}
        </button>
      {:else}
        <p class="muted text-sm">Esta pizarra no tiene una secuencia de imágenes activa.</p>
      {/if}

      <div class="form-group" style="margin-top:16px">
        <label class="form-label">Subir nueva secuencia (reemplaza la actual) — JPEG/PNG/WEBP, máx. 8MB c/u, hasta 20 imágenes</label>
        <input class="input" type="file" accept="image/jpeg,image/png,image/webp" multiple on:change={addPendingImages} />
      </div>
      {#if pendingImages.length > 0}
        <ul class="image-seq-list">
          {#each pendingImages as img, idx}
            <li class="image-seq-item">
              <span class="text-sm pending-filename">{img.file.name}</span>
              <input class="input select-sm" type="number" min="1" max="120" bind:value={img.duration_seconds} />
              <span class="muted text-sm">seg</span>
              <button type="button" class="btn btn-ghost btn-sm" on:click={() => movePendingImage(idx, -1)} disabled={idx === 0}>↑</button>
              <button type="button" class="btn btn-ghost btn-sm" on:click={() => movePendingImage(idx, 1)} disabled={idx === pendingImages.length - 1}>↓</button>
              <button type="button" class="btn btn-danger btn-sm" on:click={() => removePendingImage(idx)}>✕</button>
            </li>
          {/each}
        </ul>
        {#if uploadingImages}
          <div class="upload-progress"><div class="upload-progress-bar" style="width:{imagesUploadPct}%"></div></div>
          <p class="muted text-sm">Subiendo… {imagesUploadPct}%</p>
        {:else}
          <button type="button" class="btn btn-primary btn-sm" on:click={uploadImageSequence}>
            Subir {pendingImages.length} imagen(es)
          </button>
        {/if}
      {/if}
    </div>
  {/if}

  <div class="config-section">
    <div class="config-header"><strong>Rotación</strong></div>
    <div class="config-body">
      <div class="form-row">
        <div class="form-group">
          <label class="form-label">Turnos visibles tras el anuncio (segundos)</label>
          <input class="input" type="number" min="3" max="600" bind:value={rotationSeconds} />
        </div>
        <div class="form-group">
          <label class="form-label">Espera tras un llamado antes de reanudar (segundos)</label>
          <input class="input" type="number" min="1" max="120" bind:value={cooldownSeconds} />
        </div>
      </div>
      <button type="button" class="btn btn-primary btn-sm media-settings-save" on:click={saveMediaSettings} disabled={savingMediaSettings}>
        {savingMediaSettings ? 'Guardando…' : 'Guardar rotación'}
      </button>
    </div>
  </div>

  {#if mediaBoard?.ad_media_type && mediaBoard.ad_media_type !== 'none'}
    <div class="modal-footer">
      <button type="button" class="btn btn-danger" on:click={removeAds}>Quitar anuncio activo</button>
    </div>
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
.media-mode-toggle { display: flex; gap: 8px; margin-bottom: 16px; }
.media-section { display: flex; flex-direction: column; margin-bottom: 20px; }
.media-preview-video { width: 100%; max-height: 240px; border-radius: var(--radius-sm); background: #000; }
.upload-progress {
  width: 100%; height: 8px; background: var(--surface-2);
  border-radius: 4px; overflow: hidden; margin-top: 10px;
}
.upload-progress-bar { height: 100%; background: var(--primary); transition: width .2s ease; }
.image-seq-list { list-style: none; display: flex; flex-direction: column; gap: 6px; margin: 10px 0; }
.image-seq-item {
  display: flex; align-items: center; gap: 8px;
  padding: 6px 10px; background: var(--surface-2); border-radius: var(--radius-sm);
}
.image-seq-item .pending-filename { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.image-seq-thumb { width: 48px; height: 32px; object-fit: cover; border-radius: 4px; flex-shrink: 0; }
.media-settings-save { align-self: flex-start; margin-top: 12px; }
@keyframes spin { to { transform: rotate(360deg); } }
</style>
