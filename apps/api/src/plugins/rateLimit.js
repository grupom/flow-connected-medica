'use strict';

const fp = require('fastify-plugin');

module.exports = fp(async function rateLimitPlugin(fastify) {
    await fastify.register(require('@fastify/rate-limit'), {
        global: false,
        max: 100,
        timeWindow: '1 minute',
    });
});
