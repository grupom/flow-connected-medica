import { writable } from 'svelte/store';
import { browser } from '$app/environment';

// Non-sensitive cache of the user object only — used purely for an
// optimistic first paint (show the sidebar/name immediately on reload
// instead of a blank spinner) while a silent refresh confirms the real
// session. Never treated as authoritative: `ready` only flips true once
// refreshSession() (see api.js) actually confirms the session cookie is
// valid. Tokens themselves live in httpOnly cookies set by the server —
// there is nothing for this module to store or read for them anymore.
const USER_CACHE_KEY = 'cq_user';

function createAuthStore() {
    let initialUser = null;
    if (browser) {
        try {
            const cached = localStorage.getItem(USER_CACHE_KEY);
            if (cached) initialUser = JSON.parse(cached);
        } catch { }
    }

    const { subscribe, set, update } = writable({ user: initialUser, ready: false });

    return {
        subscribe,

        /** Called after a successful login/refresh — cookies are already set by the server. */
        setUser(user) {
            if (browser) {
                try { localStorage.setItem(USER_CACHE_KEY, JSON.stringify(user)); } catch { }
            }
            set({ user, ready: true });
        },

        /** Clear local user cache. Server-side cookie clearing happens via /api/auth/logout. */
        logout() {
            if (browser) {
                try { localStorage.removeItem(USER_CACHE_KEY); } catch { }
            }
            set({ user: null, ready: true });
        },

        /** Mark store as ready (e.g. after a failed rehydration attempt). */
        markReady() {
            update((s) => ({ ...s, ready: true }));
        },
    };
}

export const auth = createAuthStore();
