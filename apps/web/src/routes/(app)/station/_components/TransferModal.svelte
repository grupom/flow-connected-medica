<script>
  import { createEventDispatcher } from 'svelte';
  import Modal from '$lib/components/Modal.svelte';

  export let open = false;
  export let ticketCode = '';
  export let queueSettings = [];
  export let stationPrefix = '';

  let transferToPrefix = '';
  let transferReason = '';
  let submittingTransfer = false;

  const dispatch = createEventDispatcher();

  $: if (open) {
    transferToPrefix = '';
    transferReason = '';
  }

  function close() {
    dispatch('close');
  }

  async function handleSubmit() {
    if (!transferToPrefix) return;
    submittingTransfer = true;
    dispatch('transfer', { toPrefix: transferToPrefix, reason: transferReason });
  }

  export function resetSubmitting() {
    submittingTransfer = false;
  }
</script>

<Modal bind:open title="Transferir Turno" on:close={close}>
  <form on:submit|preventDefault={handleSubmit} class="modal-form">
    <p class="text-sm muted mb-16">
      Transferir turno <strong>{ticketCode}</strong> a otra cola de servicio.
      El turno actual será marcado como transferido y se generará un nuevo turno en la cola destino.
    </p>

    <div class="form-group">
      <label class="form-label" for="transfer-prefix">Servicio de Destino</label>
      <select id="transfer-prefix" class="input" bind:value={transferToPrefix} required>
        <option value="" disabled>Seleccionar servicio...</option>
        {#each queueSettings as qs}
          {#if qs.prefix !== stationPrefix && qs.service_name}
            <option value={qs.prefix}>{qs.service_name} ({qs.prefix})</option>
          {/if}
        {/each}
      </select>
    </div>

    <div class="form-group mt-16">
      <label class="form-label" for="transfer-notes">Notas (Opcional)</label>
      <textarea id="transfer-notes" class="input text-area" bind:value={transferReason} placeholder="Razón de la transferencia..."></textarea>
    </div>

    <div class="modal-footer mt-16" style="display:flex; justify-content:flex-end; gap:8px;">
      <button type="button" class="btn btn-ghost" on:click={close}>Cancelar</button>
      <button type="submit" class="btn btn-primary" disabled={submittingTransfer || !transferToPrefix}>
        {submittingTransfer ? 'Transfiriendo...' : 'Transferir Turno'}
      </button>
    </div>
  </form>
</Modal>
