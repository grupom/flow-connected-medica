<script>
    import { createEventDispatcher, onMount } from "svelte";
    export let open = false;
    export let title = "";
    export let size = "md"; // sm | md | lg

    const dispatch = createEventDispatcher();

    function close() {
        dispatch("close");
    }

    function onKeyDown(e) {
        if (e.key === "Escape") close();
    }
    onMount(() => {
        document.addEventListener("keydown", onKeyDown);
        return () => document.removeEventListener("keydown", onKeyDown);
    });

    /**
     * Portal action: moves the node to document.body so it escapes
     * any parent stacking context (e.g. sidebar transforms).
     */
    function portal(node) {
        document.body.appendChild(node);
        return {
            destroy() {
                if (node.parentNode) node.parentNode.removeChild(node);
            }
        };
    }
</script>

{#if open}
    <!-- svelte-ignore a11y-click-events-have-key-events a11y-no-static-element-interactions -->
    <div class="modal-overlay" use:portal on:click|self={close}>
        <div class="modal modal-{size}" role="dialog" aria-modal="true">
            <div class="modal-header">
                <h3>{title}</h3>
                <button class="modal-close" on:click={close} aria-label="Close"
                    >✕</button
                >
            </div>
            <div class="modal-body">
                <slot />
            </div>
            {#if $$slots.footer}
                <div class="modal-footer">
                    <slot name="footer" />
                </div>
            {/if}
        </div>
    </div>
{/if}

<style>
    .modal-overlay {
        position: fixed;
        inset: 0;
        background: rgba(15, 23, 42, 0.45);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: var(--z-modal);
        padding: 16px;
        animation: fadeIn 0.15s ease;
    }
    .modal {
        background: var(--surface);
        border-radius: var(--radius-lg);
        box-shadow: var(--shadow-xl);
        display: flex;
        flex-direction: column;
        max-height: 90vh;
        animation: fadeIn 0.15s ease;
        width: 100%;
    }
    .modal-sm {
        max-width: 420px;
    }
    .modal-md {
        max-width: 560px;
    }
    .modal-lg {
        max-width: 760px;
    }

    .modal-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 20px 24px 16px;
        border-bottom: 1px solid var(--border);
    }
    .modal-header h3 {
        font-size: 1.0625rem;
        font-weight: 700;
    }
    .modal-close {
        background: none;
        border: none;
        cursor: pointer;
        color: var(--text-muted);
        font-size: 0.875rem;
        padding: 4px 8px;
        border-radius: var(--radius-sm);
    }
    .modal-close:hover {
        background: var(--surface-2);
        color: var(--text);
    }

    .modal-body {
        padding: 20px 24px;
        overflow-y: auto;
        flex: 1;
    }
    .modal-footer {
        padding: 16px 24px 20px;
        border-top: 1px solid var(--border);
        display: flex;
        gap: 8px;
        justify-content: flex-end;
    }
</style>
