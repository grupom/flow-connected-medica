// La app es 100% client-side: deshabilitar SSR y pre-rendering globalmente.
// Esto permite usar adapter-static en modo SPA (fallback → index.html).
export const ssr = false;
export const prerender = false;
