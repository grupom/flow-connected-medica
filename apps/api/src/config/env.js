'use strict';

require('dotenv').config();

const env = {
    PORT: parseInt(process.env.PORT || '3001', 10),
    HOST: process.env.HOST || '0.0.0.0',
    DATABASE_URL: process.env.DATABASE_URL || '',
    JWT_SECRET: process.env.JWT_SECRET || 'change_me_access_secret',
    JWT_REFRESH_SECRET: process.env.JWT_REFRESH_SECRET || 'change_me_refresh_secret',
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
    NODE_ENV: process.env.NODE_ENV || 'development',
};

if (!env.DATABASE_URL) {
    console.error('FATAL: DATABASE_URL is not set in environment');
    process.exit(1);
}

module.exports = env;
