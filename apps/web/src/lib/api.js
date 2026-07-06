import { auth } from './auth.js';
import { get } from 'svelte/store';

// PUBLIC_API_URL vacío ('') → rutas relativas (/api/...) — mismo origen que el servidor.
// PUBLIC_API_URL=http://host:port → URL absoluta (útil en desarrollo con Vite standalone).
// ?? en lugar de || para que el string vacío sea respetado (|| lo ignora por ser falsy).
let API_BASE = import.meta.env.PUBLIC_API_URL ?? '';

let isRefreshing = false;
let refreshQueue = [];

function processQueue(error, token = null) {
    refreshQueue.forEach((p) => (error ? p.reject(error) : p.resolve(token)));
    refreshQueue = [];
}

async function doRefreshRequest(refreshToken) {
    const res = await fetch(`${API_BASE}/api/auth/refresh`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refreshToken }),
    });
    if (!res.ok) {
        const err = new Error(`Refresh failed with ${res.status}`);
        err.status = res.status;
        throw err;
    }
    return res.json(); // { accessToken, refreshToken, user }
}

// Retry schedule for a failed refresh caused by a network error or 5xx (NOT a
// 401 — that's treated as definitive below). ~15s total tolerates a brief API
// restart/deploy without forcing a hard logout on every open tab.
const REFRESH_RETRY_DELAYS_MS = [1000, 2000, 4000, 8000];

/**
 * Single entry point for rotating the session's tokens — shared by
 * apiFetch's 401 handler AND the app-shell rehydration in
 * (app)/+layout.svelte, so there is only ever one refresh call in flight
 * per tab (cross-tab coordination lives in auth.js's storage listener).
 * Previously +layout.svelte called the refresh endpoint directly, bypassing
 * this mutex, which let two refresh requests race the backend and log the
 * loser out well before the refresh token's real expiry.
 *
 * Retries with backoff (~15s total) on a network error or 5xx before giving
 * up — only an explicit 401 (token genuinely revoked/expired) is treated as
 * fatal immediately.
 *
 * @returns {Promise<{accessToken:string, refreshToken:string, user:object}>}
 */
export async function refreshSession() {
    if (isRefreshing) {
        const accessToken = await new Promise((resolve, reject) => {
            refreshQueue.push({ resolve, reject });
        });
        return { accessToken, refreshToken: auth.getRefreshToken(), user: get(auth).user };
    }

    const refreshToken = auth.getRefreshToken();
    if (!refreshToken) {
        const err = new Error('No refresh token');
        err.status = 401;
        throw err;
    }

    isRefreshing = true;
    try {
        let result;
        try {
            result = await doRefreshRequest(refreshToken);
        } catch (err) {
            if (err.status === 401) {
                // A 401 here can legitimately mean another tab already
                // rotated this exact token (see auth.js's storage listener)
                // rather than the session actually being dead. If the
                // stored refresh token has since changed out from under us,
                // trust that tab's rotation instead of logging out.
                const currentToken = auth.getRefreshToken();
                if (currentToken && currentToken !== refreshToken) {
                    const current = get(auth);
                    result = { accessToken: current.accessToken, refreshToken: currentToken, user: current.user };
                } else {
                    throw err; // definitive — not worth retrying
                }
            } else {
                // Transient (network hiccup / 5xx, e.g. the API restarting mid-deploy) —
                // retry with backoff before giving up.
                for (const delay of REFRESH_RETRY_DELAYS_MS) {
                    await new Promise((r) => setTimeout(r, delay));
                    try {
                        result = await doRefreshRequest(refreshToken);
                        break;
                    } catch (retryErr) {
                        err = retryErr;
                        if (retryErr.status === 401) break; // now definitive — stop retrying
                    }
                }
                if (!result) throw err;
            }
        }
        if (result.accessToken !== get(auth).accessToken) auth.setAuth(result);
        processQueue(null, result.accessToken);
        return result;
    } catch (err) {
        processQueue(err);
        throw err;
    } finally {
        isRefreshing = false;
    }
}

/**
 * Core fetch wrapper with automatic 401 → token refresh → retry.
 *
 * @param {string} path  - Path relative to API_BASE (e.g. '/api/auth/login')
 * @param {RequestInit} [options]
 * @returns {Promise<any>}  Parsed JSON
 */
async function apiFetch(path, options = {}) {
    const { accessToken } = get(auth);

    const headers = {
        // FormData bodies must NOT get an explicit Content-Type — the browser sets
        // "multipart/form-data; boundary=..." itself, which we can't replicate here.
        ...(options.body && !(options.body instanceof FormData) ? { 'Content-Type': 'application/json' } : {}),
        ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
        ...options.headers,
    };

    let res = await fetch(`${API_BASE}${path}`, { ...options, headers });

    // ── Token expired → try refresh ───────────────────────────────────────
    if (res.status === 401) {
        let newAccessToken;
        try {
            ({ accessToken: newAccessToken } = await refreshSession());
        } catch (err) {
            auth.logout();
            if (typeof window !== 'undefined') window.location.href = '/login';
            throw new Error('Session expired');
        }

        headers['Authorization'] = `Bearer ${newAccessToken}`;
        res = await fetch(`${API_BASE}${path}`, { ...options, headers });
    }

    // ── Parse response ────────────────────────────────────────────────────
    const text = await res.text();
    let data;
    try { data = JSON.parse(text); } catch { data = text; }

    if (!res.ok) {
        // Los errores de validación de Fastify traen el detalle específico (ej. "password: must
        // NOT have fewer than 6 characters") en `details`; el `message` de arriba es genérico.
        const detail = data?.details?.[0];
        const message = (detail && `${detail.instancePath?.replace(/^\//, '') || 'campo'}: ${detail.message}`)
            || data?.message || data?.error || `HTTP ${res.status}`;
        throw Object.assign(new Error(message), { status: res.status, data });
    }

    return data;
}

// ── Convenience wrappers ──────────────────────────────────────────────────

export const api = {
    get: (path, opts = {}) => apiFetch(path, { method: 'GET', ...opts }),

    post: (path, body, opts = {}) =>
        apiFetch(path, { method: 'POST', body: JSON.stringify(body), ...opts }),

    put: (path, body, opts = {}) =>
        apiFetch(path, { method: 'PUT', body: JSON.stringify(body), ...opts }),

    patch: (path, body, opts = {}) =>
        apiFetch(path, { method: 'PATCH', body: JSON.stringify(body), ...opts }),

    delete: (path, opts = {}) => apiFetch(path, { method: 'DELETE', ...opts }),

    /**
     * Multipart upload with progress reporting — fetch() has no upload.onprogress,
     * so this uses XMLHttpRequest instead of going through apiFetch. Intentional
     * simplification: does not share apiFetch's 401-refresh mutex; on an expired
     * token the caller gets a 401 and can retry after a normal navigation refreshes it.
     * Acceptable here since uploads are an admin-only, low-frequency action.
     */
    upload: (path, formData, { onProgress } = {}) => {
        return new Promise((resolve, reject) => {
            const xhr = new XMLHttpRequest();
            xhr.open('POST', `${API_BASE}${path}`);
            const { accessToken } = get(auth);
            if (accessToken) xhr.setRequestHeader('Authorization', `Bearer ${accessToken}`);
            xhr.upload.onprogress = (e) => {
                if (e.lengthComputable) onProgress?.(e.loaded, e.total);
            };
            xhr.onload = () => {
                let data;
                try { data = JSON.parse(xhr.responseText); } catch { data = xhr.responseText; }
                if (xhr.status >= 200 && xhr.status < 300) {
                    resolve(data);
                } else {
                    const message = data?.message || data?.error || `HTTP ${xhr.status}`;
                    reject(Object.assign(new Error(message), { status: xhr.status, data }));
                }
            };
            xhr.onerror = () => reject(new Error('Network error'));
            xhr.send(formData);
        });
    },

    /** Raw fetch without auth header (for login, public routes) */
    public: {
        get: (path) =>
            fetch(`${API_BASE}${path}`).then(async (r) => {
                const json = await r.json();
                if (!r.ok) throw Object.assign(new Error(json.message || 'Error'), { data: json });
                return json;
            }),
        post: (path, body) =>
            fetch(`${API_BASE}${path}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body),
            }).then(async (r) => {
                const json = await r.json();
                if (!r.ok) throw Object.assign(new Error(json.message || 'Error'), { data: json });
                return json;
            }),
    },
};
