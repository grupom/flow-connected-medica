<script>
  export let stats = { waiting: 0, serving: 0, done: 0, noShow: 0 };
</script>

<div class="stats-panel">
  <div class="stat-card stat-waiting">
    <span class="stat-icon">⏳</span>
    <span class="stat-num">{stats.waiting}</span>
    <span class="stat-label">En Espera</span>
  </div>
  <div class="stat-card stat-serving">
    <span class="stat-icon">🩺</span>
    <span class="stat-num">{stats.serving}</span>
    <span class="stat-label">Atendiendo</span>
  </div>
  <div class="stat-card stat-done">
    <span class="stat-icon">✅</span>
    <span class="stat-num">{stats.done}</span>
    <span class="stat-label">Completados</span>
  </div>
  <div class="stat-card stat-noshow">
    <span class="stat-icon">🚫</span>
    <span class="stat-num">{stats.noShow}</span>
    <span class="stat-label">No-Show</span>
  </div>
</div>

<style>
.stats-panel {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;
}
.stat-card {
  background: white;
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  padding: 16px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  min-width: 100px;
  box-shadow: var(--shadow-sm);
}
.stat-icon { font-size: 1.25rem; }
.stat-num {
  font-size: 1.75rem;
  font-weight: 800;
  line-height: 1;
}
.stat-label {
  font-size: .7rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: .05em;
  color: var(--text-muted);
}
.stat-waiting .stat-num { color: #f59e0b; }
.stat-serving .stat-num { color: #22c55e; }
.stat-done .stat-num { color: var(--primary); }
.stat-noshow .stat-num { color: #ef4444; }

@media (max-width: 900px) {
  .stats-panel {
    grid-template-columns: repeat(2, 1fr);
  }
}
</style>
