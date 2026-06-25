<script>
    /**
     * KPI card with gradient background, icon, big number, label.
     * @prop {string} label
     * @prop {string|number} value
     * @prop {string} icon   - emoji or svg string
     * @prop {'blue'|'orange'|'green'|'purple'} color
     * @prop {string} [sub]  - small sub-text below value
     */
    export let label = "";
    export let value = "—";
    export let icon = "📊";
    export let color = "blue";
    export let sub = "";
</script>

<div class="kpi-card kpi-{color}">
    <div class="kpi-left">
        <p class="kpi-label">{label}</p>
        <p class="kpi-value">{value}</p>
        {#if sub}<p class="kpi-sub">{sub}</p>{/if}
    </div>
    <div class="kpi-icon">{icon}</div>
</div>

<style>
    .kpi-card {
        border-radius: var(--radius-lg);
        padding: 22px 24px;
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 12px;
        position: relative;
        overflow: hidden;
        box-shadow: var(--shadow-md);
        transition:
            transform var(--transition),
            box-shadow var(--transition);
    }
    .kpi-card:hover {
        transform: translateY(-2px);
        box-shadow: var(--shadow-lg);
    }

    .kpi-blue {
        background: linear-gradient(135deg, #3b82f6, #60a5fa);
        color: #fff;
    }
    .kpi-orange {
        background: linear-gradient(135deg, #f97316, #fb923c);
        color: #fff;
    }
    .kpi-green {
        background: linear-gradient(135deg, #10b981, #34d399);
        color: #fff;
    }
    .kpi-purple {
        background: linear-gradient(135deg, #8b5cf6, #a78bfa);
        color: #fff;
    }

    .kpi-left {
        display: flex;
        flex-direction: column;
        gap: 4px;
    }
    .kpi-label {
        font-size: 0.8125rem;
        font-weight: 500;
        opacity: 0.85;
    }
    .kpi-value {
        font-size: 2rem;
        font-weight: 700;
        line-height: 1;
    }
    .kpi-sub {
        font-size: 0.75rem;
        opacity: 0.75;
    }

    .kpi-icon {
        font-size: 2rem;
        opacity: 0.7;
        flex-shrink: 0;
    }
</style>
