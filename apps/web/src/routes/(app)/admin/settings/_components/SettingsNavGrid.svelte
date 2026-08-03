<script>
  const sections = [
    {
      href:    '/admin/stations',
      icon:    '🖥️',
      title:   'Stations',
      desc:    'Configura las estaciones de atención y operadores.',
    },
    {
      href:    '/admin/kiosks',
      icon:    '🎟️',
      title:   'Kiosks',
      desc:    'Gestiona los quioscos de autoservicio y sus colas habilitadas.',
    },
    {
      href:    '/admin/roles',
      icon:    '🔑',
      title:   'Roles',
      desc:    'Define los roles del sistema y sus permisos de acceso.',
    },
    {
      href:    '/admin/users',
      icon:    '👥',
      title:   'Users',
      desc:    'Administra los usuarios, credenciales y roles asignados.',
    },
    {
      href:    '/admin/queue-settings',
      icon:    '⚙️',
      title:   'Module Prefixes',
      desc:    'Configura los prefijos de cola, reglas de generación de turnos y prioridades.',
    },
    {
      href:    '/admin/settings/language',
      icon:    '🌐',
      title:   'Idiomas',
      desc:    'Activa o desactiva el soporte multi-idioma (Español / Kreyòl Ayisyen).',
    },
  ];
</script>

<div class="settings-grid">
  {#each sections as s}
    <a href={s.href} class="setting-card">
      <div class="card-icon">{s.icon}</div>
      <div class="card-body">
        <span class="card-title">{s.title}</span>
        <span class="card-desc">{s.desc}</span>
      </div>
      <span class="card-arrow">→</span>
    </a>
  {/each}
</div>

<style>
.settings-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 16px;
  margin-top: 8px;
}

.setting-card {
  display: flex;
  align-items: center;
  gap: 16px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  padding: 20px;
  text-decoration: none;
  color: inherit;
  transition: border-color 0.15s, box-shadow 0.15s, transform 0.15s;
  box-shadow: var(--shadow-sm);
  cursor: pointer;
}

.setting-card:hover {
  border-color: var(--primary);
  box-shadow: 0 4px 16px rgba(59, 130, 246, 0.12);
  transform: translateY(-2px);
}

.card-icon {
  font-size: 2rem;
  width: 52px;
  height: 52px;
  background: var(--primary-light);
  border-radius: var(--radius);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.card-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.card-title {
  font-size: 0.9375rem;
  font-weight: 700;
  color: var(--text);
}

.card-desc {
  font-size: 0.8rem;
  color: var(--text-muted);
  line-height: 1.45;
}

.card-arrow {
  font-size: 1.1rem;
  color: var(--text-muted);
  transition: color 0.15s, transform 0.15s;
  flex-shrink: 0;
}

.setting-card:hover .card-arrow {
  color: var(--primary);
  transform: translateX(3px);
}

@media (max-width: 600px) {
  .settings-grid { grid-template-columns: 1fr; }
}
</style>
