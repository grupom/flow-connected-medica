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

        /** Update access token after a refresh rotation */
        setTokens({ accessToken, refreshToken }) {
            update((s) => {
                const newState = { ...s, accessToken };
                if (browser) {
                    if (refreshToken) {
                        try { localStorage.setItem(STORAGE_KEY, refreshToken); } catch { }
                    }
                    try { localStorage.setItem(AUTH_KEY, JSON.stringify({ user: newState.user, accessToken })); } catch { }
                }
                return newState;
            });
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
