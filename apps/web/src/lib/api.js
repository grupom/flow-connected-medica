import { auth } from './auth.js';

// PUBLIC_API_URL vacío ('') → rutas relativas (/api/...) — mismo origen que el servidor.
// PUBLIC_API_URL=http://host:port → URL absoluta (útil en desarrollo con Vite standalone).
// ?? en lugar de || para que el string vacío sea respetado (|| lo ignora por ser falsy).
// NOTA: con cookies sameSite=lax, el modo standalone (host distinto del proxy
// de Vite) ya no recibe la cookie de sesión — solo el proxy de Vite (mismo
// origen percibido por el navegador) funciona para el flujo de auth ahora.
let API_BASE = import.meta.env.PUBLIC_API_URL ?? '';

let isRefreshing = false;
let refreshQueue = [];

function processQueue(error, user = null) {
    refreshQueue.forEach((p) => (error ? p.reject(error) : p.resolve(user)));
    refreshQueue = [];
}

async function doRefreshRequest() {
    // No body — the refresh cookie (cq_refresh_token, scoped to /api/auth)
    // rides along automatically via credentials: 'include'.
    const res = await fetch(`${API_BASE}/api/auth/refresh`, {
        method: 'POST',
        credentials: 'include',
    });
    if (!res.ok) {
        const err = new Error(`Refresh failed with ${res.status}`);
        err.status = res.status;
        throw err;
    }
    return res.json(); // { user } — access/refresh cookies arrive via Set-Cookie, not the body
}

// Retry schedule for a failed refresh caused by a network error or 5xx (NOT a
// 401 — that's treated as definitive below). ~15s total tolerates a brief API
// restart/deploy without forcing a hard logout on every open tab.
const REFRESH_RETRY_DELAYS_MS = [1000, 2000, 4000, 8000];

/**
 * Single entry point for rotating the session — shared by apiFetch's 401
 * handler AND the app-shell rehydration in (app)/+layout.svelte, so there is
 * only ever one refresh call in flight per tab. Cross-tab coordination needs
 * no explicit code now: the httpOnly refresh cookie is shared by the browser
 * across every tab automatically, so a rotation or logout in one tab is
 * simply reflected in whatever the next request from any other tab sends.
 *
 * Retries with backoff (~15s total) on a network error or 5xx before giving
 * up — only an explicit 401 (cookie genuinely missing/revoked/expired) is
 * treated as fatal immediately.
 *
 * @returns {Promise<{user: object}>}
 */
export async function refreshSession() {
    if (isRefreshing) {
        const user = await new Promise((resolve, reject) => {
            refreshQueue.push({ resolve, reject });
        });
        return { user };
    }

    isRefreshing = true;
    try {
        let result;
        try {
            result = await doRefreshRequest();
        } catch (err) {
            if (err.status === 401) {
                throw err; // definitive — no cookie, or it's genuinely dead
            }
            // Transient (network hiccup / 5xx, e.g. the API restarting mid-deploy) —
            // retry with backoff before giving up.
            for (const delay of REFRESH_RETRY_DELAYS_MS) {
                await new Promise((r) => setTimeout(r, delay));
                try {
                    result = await doRefreshRequest();
                    break;
                } catch (retryErr) {
                    err = retryErr;
                    if (retryErr.status === 401) break; // now definitive — stop retrying
                }
            }
            if (!result) throw err;
        }
        auth.setUser(result.user);
        processQueue(null, result.user);
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
    const headers = {
        // FormData bodies must NOT get an explicit Content-Type — the browser sets
        // "multipart/form-data; boundary=..." itself, which we can't replicate here.
        ...(options.body && !(options.body instanceof FormData) ? { 'Content-Type': 'application/json' } : {}),
        ...options.headers,
    };

    let res = await fetch(`${API_BASE}${path}`, { ...options, headers, credentials: 'include' });

    // ── Session cookie expired → try refresh ──────────────────────────────
    if (res.status === 401) {
        try {
            await refreshSession();
        } catch (err) {
            auth.logout();
            if (typeof window !== 'undefined') window.location.href = '/login';
            throw new Error('Session expired');
        }
        res = await fetch(`${API_BASE}${path}`, { ...options, headers, credentials: 'include' });
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
     * session the caller gets a 401 and can retry after a normal navigation refreshes it.
     * Acceptable here since uploads are an admin-only, low-frequency action.
     */
    upload: (path, formData, { onProgress } = {}) => {
        return new Promise((resolve, reject) => {
            const xhr = new XMLHttpRequest();
            xhr.open('POST', `${API_BASE}${path}`);
            xhr.withCredentials = true;
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
            fetch(`${API_BASE}${path}`, { credentials: 'include' }).then(async (r) => {
                const json = await r.json();
                if (!r.ok) throw Object.assign(new Error(json.message || 'Error'), { data: json });
                return json;
            }),
        post: (path, body) =>
            fetch(`${API_BASE}${path}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                body: JSON.stringify(body),
            }).then(async (r) => {
                const json = await r.json();
                if (!r.ok) throw Object.assign(new Error(json.message || 'Error'), { data: json });
                return json;
            }),
    },
};
