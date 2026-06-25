import { writable } from 'svelte/store';

// ── Toast store ───────────────────────────────────────────────────────────
function createToastStore() {
    const { subscribe, update } = writable([]);
    let id = 0;

    return {
        subscribe,
        add(message, type = 'info', duration = 3500) {
            const toast = { id: ++id, message, type };
            update((list) => [...list, toast]);
            setTimeout(() => this.remove(toast.id), duration);
        },
        success(msg, dur) { this.add(msg, 'success', dur); },
        error(msg, dur) { this.add(msg, 'danger', dur); },
        warn(msg, dur) { this.add(msg, 'warning', dur); },
        remove(toastId) {
            update((list) => list.filter((t) => t.id !== toastId));
        },
    };
}

export const toasts = createToastStore();

// ── Sidebar collapsed state ───────────────────────────────────────────────
export const sidebarOpen = writable(true);

// ── System settings (loaded from API on app init) ─────────────────────────
export const systemSettings = writable({ multi_language: false });
