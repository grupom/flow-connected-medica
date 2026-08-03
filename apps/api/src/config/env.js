'use strict';

require('dotenv').config();

const env = {
    PORT: parseInt(process.env.PORT || '3001', 10),
    HOST: process.env.HOST || '0.0.0.0',
    DATABASE_URL: process.env.DATABASE_URL || '',
    JWT_SECRET: process.env.JWT_SECRET || '',
    JWT_REFRESH_SECRET: process.env.JWT_REFRESH_SECRET || '',
    JWT_ACCESS_EXPIRY: process.env.JWT_ACCESS_EXPIRY || '15m',
    JWT_REFRESH_EXPIRY: process.env.JWT_REFRESH_EXPIRY || '7d',
    CORS_ORIGIN: (process.env.CORS_ORIGIN || 'http://localhost:5173')
        .split(',')
        .map((s) => s.trim()),
    // CORS_SUBNETS: comma-separated network prefixes (e.g. "172.16.,10.25.1.")
    // Any origin whose host starts with one of these prefixes is allowed.
    CORS_SUBNETS: (process.env.CORS_SUBNETS || '')
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean),
    // CORS_TRUST_LAN: opt-in (default off). When true, restores the old
    // behavior of trusting any RFC1918/loopback origin. Off by default so
    // the API doesn't trust arbitrary devices on the same network — see
    // plugins/cors.js for the recommended CORS_ORIGIN/CORS_SUBNETS path.
    CORS_TRUST_LAN: process.env.CORS_TRUST_LAN === 'true',
    // COOKIE_SECURE: opt-in (default false). Adds the `Secure` attribute to the
    // access/refresh cookies, which browsers then refuse to send over plain
    // HTTP. Default false because this app's documented deployment (Dockerfile
    // + docker-compose.yml) serves plain HTTP on the clinic's internal LAN with
    // no TLS/reverse-proxy — defaulting to true would silently break login.
    // Set to "true" only once a TLS-terminating reverse proxy sits in front.
    COOKIE_SECURE: process.env.COOKIE_SECURE === 'true',
    NODE_ENV: process.env.NODE_ENV || 'development',
};

if (!env.DATABASE_URL) {
    console.error('FATAL: DATABASE_URL is not set in environment');
    process.exit(1);
}

// No hardcoded default here on purpose: a fallback secret baked into the
// source would let anyone forge valid access/refresh tokens the moment a
// deployment loses its env vars. Fail loudly instead, same as DATABASE_URL.
if (!env.JWT_SECRET || !env.JWT_REFRESH_SECRET) {
    console.error('FATAL: JWT_SECRET and JWT_REFRESH_SECRET must be set in environment');
    process.exit(1);
}

if (env.JWT_SECRET.length < 32 || env.JWT_REFRESH_SECRET.length < 32) {
    console.error('FATAL: JWT_SECRET and JWT_REFRESH_SECRET must be at least 32 characters long');
    process.exit(1);
}

module.exports = env;
