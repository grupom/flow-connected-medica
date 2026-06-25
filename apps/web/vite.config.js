import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
    plugins: [sveltekit()],
    server: {
        port: 5173,
        host: '0.0.0.0',
        // En desarrollo el API corre en :3001; el proxy reenvía /api y /health
        // para que la web use rutas relativas igual que en producción.
        proxy: {
            '/api': {
                target: 'http://localhost:3001',
                changeOrigin: true,
            },
            '/health': {
                target: 'http://localhost:3001',
                changeOrigin: true,
            },
        },
    },
});
