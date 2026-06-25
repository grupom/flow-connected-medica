<script>
    import { toasts } from "$lib/stores.js";
</script>

{#if $toasts.length > 0}
    <div class="toast-container">
        {#each $toasts as toast (toast.id)}
            <div class="toast toast-{toast.type}" role="alert">
                <span class="toast-icon">
                    {#if toast.type === "success"}✅
                    {:else if toast.type === "danger"}❌
                    {:else if toast.type === "warning"}⚠️
                    {:else}ℹ️{/if}
                </span>
                <span class="toast-msg">{toast.message}</span>
                <button
                    class="toast-close"
                    on:click={() => toasts.remove(toast.id)}>✕</button
                >
            </div>
        {/each}
    </div>
{/if}

<style>
    .toast-container {
        position: fixed;
        bottom: 24px;
        right: 24px;
        display: flex;
        flex-direction: column;
        gap: 8px;
        z-index: var(--z-toast);
        max-width: 360px;
        width: 100%;
    }
    .toast {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 12px 14px;
        border-radius: var(--radius-sm);
        background: var(--surface);
        box-shadow: var(--shadow-lg);
        border-left: 4px solid var(--primary);
        font-size: 0.875rem;
        animation: slideInRight 0.2s ease both;
    }
    .toast-success {
        border-left-color: var(--success);
    }
    .toast-danger {
        border-left-color: var(--danger);
    }
    .toast-warning {
        border-left-color: var(--warning);
    }

    .toast-msg {
        flex: 1;
        color: var(--text);
        font-weight: 500;
    }
    .toast-close {
        background: none;
        border: none;
        cursor: pointer;
        color: var(--text-muted);
        font-size: 0.75rem;
        padding: 2px 4px;
    }
    .toast-close:hover {
        color: var(--text);
    }
</style>
