import adapter from '@sveltejs/adapter-static';

/** @type {import('@sveltejs/kit').Config} */
const config = {
    kit: {
        adapter: adapter({
            pages: 'build',
            assets: 'build',
            fallback: 'index.html', // SPA mode: rutas desconocidas → index.html
            precompress: false,
            strict: false,
        }),
        alias: {
            $components: 'src/lib/components',
            $lib: 'src/lib',
        },
    },
};

export default config;
