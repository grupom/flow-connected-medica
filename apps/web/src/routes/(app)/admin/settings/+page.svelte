<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';
  import ConfigSectionCard from '$lib/components/ConfigSectionCard.svelte';
  import SettingsNavGrid from './_components/SettingsNavGrid.svelte';
  import FactoryResetPanel from './_components/FactoryResetPanel.svelte';

  // ── Ticket settings ────────────────────────────────────────
  let ticketCompanyName = '';
  let savingTicket = false;

  // ── Session duration settings ─────────────────────────────
  let sessionDurationHours = 12;
  let kioskNoExpiry = true;
  let savingSession = false;

  // ── No-Show requeue settings ───────────────────────────────
  let noShowRequeueLimit = 3;
  let savingNoShow = false;

  onMount(async () => {
    try {
      const res = await api.get('/api/admin/settings');
      ticketCompanyName = res.data?.ticket_company_name ?? '';
      sessionDurationHours = res.data?.session_duration_hours_staff ?? 12;
      kioskNoExpiry = res.data?.session_kiosk_no_expiry ?? true;
      noShowRequeueLimit = res.data?.no_show_requeue_limit ?? 3;
    } catch {
      // non-critical
    }
  });

  async function saveTicketSettings() {
    savingTicket = true;
    try {
      await api.patch('/api/admin/settings', {
        ticket_company_name: ticketCompanyName.trim()
      });
      toasts.success('Configuración del ticket guardada');
    } catch (e) {
      toasts.error(e.message || 'Error al guardar');
    } finally {
      savingTicket = false;
    }
  }

  async function saveSessionSettings() {
    const hours = Math.min(16, Math.max(8, Math.round(sessionDurationHours)));
    sessionDurationHours = hours;
    savingSession = true;
    try {
      await api.patch('/api/admin/settings', {
        session_duration_hours_staff: hours,
        session_kiosk_no_expiry: kioskNoExpiry,
      });
      toasts.success('Configuración de sesión guardada');
    } catch (e) {
      toasts.error(e.message || 'Error al guardar');
    } finally {
      savingSession = false;
    }
  }

  async function saveNoShowSettings() {
    const limit = Math.min(20, Math.max(1, Math.round(noShowRequeueLimit)));
    noShowRequeueLimit = limit;
    savingNoShow = true;
    try {
      await api.patch('/api/admin/settings', { no_show_requeue_limit: limit });
      toasts.success('Límite de reinserción guardado');
    } catch (e) {
      toasts.error(e.message || 'Error al guardar');
    } finally {
      savingNoShow = false;
    }
  }
</script>

<svelte:head>
  <title>Settings — Flow Connected</title>
</svelte:head>

<div class="page-header">
  <h2 class="page-title">Settings</h2>
  <p class="page-subtitle">Configuración y administración del sistema</p>
</div>

<SettingsNavGrid />

<!-- ── Ticket config ────────────────────────────────────────── -->
<ConfigSectionCard
  icon="🖨️"
  title="Configuración del Ticket"
  subtitle="Personaliza el encabezado que aparece en el ticket impreso"
  saving={savingTicket}
  on:save={saveTicketSettings}
>
  <div class="config-field">
    <label class="config-label" for="company-name">
      Nombre de la empresa
      <span class="config-hint">Aparece encima de "FLOW CONNECTED" en el ticket</span>
    </label>
    <div class="config-input-row">
      <input
        id="company-name"
        class="input"
        type="text"
        bind:value={ticketCompanyName}
        placeholder="Ej. MEDICA"
        maxlength="40"
        on:keydown={e => e.key === 'Enter' && saveTicketSettings()}
      />
    </div>
    {#if ticketCompanyName.trim()}
      <div class="ticket-preview">
        <span class="tp-company">{ticketCompanyName.trim().toUpperCase()}</span>
        <span class="tp-brand">FLOW CONNECTED</span>
      </div>
    {/if}
  </div>
</ConfigSectionCard>

<!-- ── Session duration config ──────────────────────────────── -->
<ConfigSectionCard
  icon="⏱️"
  title="Duración de Sesión"
  subtitle="Controla cuánto dura una sesión iniciada antes de requerir volver a ingresar credenciales"
  saving={savingSession}
  on:save={saveSessionSettings}
>
  <div class="config-field">
    <label class="config-label" for="session-hours">
      Operador / Front-desk / Admin (horas)
      <span class="config-hint">Entre 8 y 16 horas — aplica a todas las estaciones de personal por igual</span>
    </label>
    <div class="config-input-row">
      <input
        id="session-hours"
        class="input"
        type="number"
        min="8"
        max="16"
        step="1"
        bind:value={sessionDurationHours}
      />
      <span class="config-hint">horas</span>
    </div>
  </div>

  <div class="config-field">
    <label class="config-checkbox-row" for="kiosk-no-expiry">
      <input
        id="kiosk-no-expiry"
        type="checkbox"
        bind:checked={kioskNoExpiry}
      />
      <span>
        El kiosko nunca cierra sesión automáticamente
        <span class="config-hint">La sesión del kiosko solo termina si alguien cierra sesión manualmente</span>
      </span>
    </label>
  </div>
</ConfigSectionCard>

<!-- ── No-Show requeue config ───────────────────────────────── -->
<ConfigSectionCard
  icon="↩️"
  title="Reinserción de Turnos No-Show"
  subtitle='Controla hasta cuándo un turno marcado como "No-Show" puede volver a la cola de espera'
  saving={savingNoShow}
  on:save={saveNoShowSettings}
>
  <div class="config-field">
    <label class="config-label" for="noshow-limit">
      Límite de turnos llamados
      <span class="config-hint">
        Si ya se llamaron más turnos que este número después del No-Show (ej. C07 en
        No-Show, límite 3: se puede reinsertar hasta que llamen C10; desde C11 en
        adelante queda bloqueado), ya no podrá reinsertarse.
      </span>
    </label>
    <div class="config-input-row">
      <input
        id="noshow-limit"
        class="input"
        type="number"
        min="1"
        max="20"
        step="1"
        bind:value={noShowRequeueLimit}
      />
      <span class="config-hint">turnos</span>
    </div>
  </div>
</ConfigSectionCard>

<FactoryResetPanel />

<style>
.config-field { display: flex; flex-direction: column; gap: 8px; }

.config-label {
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--text);
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.config-hint {
  font-size: 0.75rem;
  font-weight: 400;
  color: var(--text-muted);
}

.config-input-row {
  display: flex;
  gap: 10px;
  align-items: center;
  max-width: 480px;
}

.config-input-row .input { flex: 1; }
.config-input-row .input[type="number"] { flex: 0 0 100px; }

.config-checkbox-row {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  cursor: pointer;
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--text);
}
.config-checkbox-row input[type="checkbox"] {
  margin-top: 3px;
  width: 16px;
  height: 16px;
  flex-shrink: 0;
  cursor: pointer;
}

/* Mini ticket preview */
.ticket-preview {
  display: inline-flex;
  flex-direction: column;
  align-items: center;
  gap: 1px;
  background: #f8fafc;
  border: 1px dashed var(--border);
  border-radius: var(--radius);
  padding: 8px 20px;
  margin-top: 4px;
  width: fit-content;
}

.tp-company {
  font-size: 0.7rem;
  font-weight: 800;
  letter-spacing: 0.12em;
  color: var(--text);
}

.tp-brand {
  font-size: 0.6rem;
  font-weight: 600;
  letter-spacing: 0.1em;
  color: var(--text-muted);
}
</style>
