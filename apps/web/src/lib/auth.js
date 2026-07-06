import { writable } from 'svelte/store';
import { browser } from '$app/environment';

const STORAGE_KEY = 'cq_refresh';
const AUTH_KEY = 'cq_auth'; // for user and accessToken

function createAuthStore() {
    let initialAuth = { user: null, accessToken: null, ready: false };

    if (browser) {
        try {
            const storedAuth = localStorage.getItem(AUTH_KEY);
            if (storedAuth) {
                const parsed = JSON.parse(storedAuth);
                initialAuth = { ...initialAuth, ...parsed, ready: true };
            }
        } catch { }
    }

    const { subscribe, set, update } = writable(initialAuth);

    // Cross-tab sync: the `storage` event fires in OTHER tabs of the same
    // origin (never the tab that made the change) whenever localStorage is
    // written. Without this, a tab that loses a refresh-token race against
    // another tab/monitor of the same session (see api.js refreshSession())
    // never learns the token was rotated elsewhere and gets logged out on
    // its next refresh attempt even though the session is still alive.
    if (browser) {
        window.addEventListener('storage', (event) => {
            if (event.key !== AUTH_KEY && event.key !== STORAGE_KEY) return;
            try {
                const storedAuth = localStorage.getItem(AUTH_KEY);
                if (!storedAuth) {
                    set({ user: null, accessToken: null, ready: true });
                    return;
                }
                const parsed = JSON.parse(storedAuth);
                update((s) => ({ ...s, user: parsed.user, accessToken: parsed.accessToken, ready: true }));
            } catch { }
        });
    }

    return {
        subscribe,

        /** Called after successful login */
        setAuth({ user, accessToken, refreshToken }) {
            if (browser) {
                if (refreshToken) {
                    try { localStorage.setItem(STORAGE_KEY, refreshToken); } catch { }
                }
                try { localStorage.setItem(AUTH_KEY, JSON.stringify({ user, accessToken })); } catch { }
            }
            set({ user, accessToken, ready: true });
        },

        /** Clear auth state and stored refresh token */
        logout() {
            if (browser) {
                try { 
                    localStorage.removeItem(STORAGE_KEY); 
                    localStorage.removeItem(AUTH_KEY);
                } catch { }
            }
            set({ user: null, accessToken: null, ready: true });
        },

        /** Returns the stored refresh token string or null */
        getRefreshToken() {
            if (browser) {
                try { return localStorage.getItem(STORAGE_KEY); } catch { return null; }
            }
            return null;
        },

        /** Mark store as ready (e.g. after failed rehydration) */
        markReady() {
            update((s) => ({ ...s, ready: true }));
        },
    };
}

export const auth = createAuthStore();
