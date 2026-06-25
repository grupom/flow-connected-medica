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
        ...(options.body ? { 'Content-Type': 'application/json' } : {}),
        ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
        ...options.headers,
    };

    let res = await fetch(`${API_BASE}${path}`, { ...options, headers });

    // ── Token expired → try refresh ───────────────────────────────────────
    if (res.status === 401) {
        const refreshToken = auth.getRefreshToken();
        if (!refreshToken) {
            auth.logout();
            if (typeof window !== 'undefined') window.location.href = '/login';
            throw new Error('Session expired');
        }

        if (isRefreshing) {
            // Queue concurrent requests until refresh resolves
            const newToken = await new Promise((resolve, reject) => {
                refreshQueue.push({ resolve, reject });
            });
            headers['Authorization'] = `Bearer ${newToken}`;
            res = await fetch(`${API_BASE}${path}`, { ...options, headers });
        } else {
            isRefreshing = true;
            try {
                const rfRes = await fetch(`${API_BASE}/api/auth/refresh`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ refreshToken }),
                });
                if (!rfRes.ok) throw new Error('Refresh failed');
                const { accessToken: newAccess, refreshToken: newRefresh } = await rfRes.json();
                auth.setTokens({ accessToken: newAccess, refreshToken: newRefresh });
                processQueue(null, newAccess);

                headers['Authorization'] = `Bearer ${newAccess}`;
                res = await fetch(`${API_BASE}${path}`, { ...options, headers });
            } catch (err) {
                processQueue(err);
                auth.logout();
                if (typeof window !== 'undefined') window.location.href = '/login';
                throw err;
            } finally {
                isRefreshing = false;
            }
        }
    }

    // ── Parse response ────────────────────────────────────────────────────
    const text = await res.text();
    let data;
    try { data = JSON.parse(text); } catch { data = text; }

    if (!res.ok) {
        const message = data?.message || data?.error || `HTTP ${res.status}`;
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
