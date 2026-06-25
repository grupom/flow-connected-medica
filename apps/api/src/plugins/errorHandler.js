'use strict';

const fp = require('fastify-plugin');

module.exports = fp(async function errorHandler(fastify) {
    fastify.setErrorHandler(function (error, request, reply) {
        const statusCode = error.statusCode || error.status || 500;

        if (error.validation) {
            return reply.code(400).send({
                error: 'Validation Error',
                message: 'Request validation failed',
                details: error.validation,
            });
        }

        if (statusCode >= 500) {
            request.log.error({ err: error }, 'Internal server error');
        }

        return reply.code(statusCode).send({
            error: error.name || 'Error',
            message: error.message || 'An unexpected error occurred',
            details: error.details || null,
        });
    });

    // setNotFoundHandler se registra en server.js junto con el Web UI
    // para poder diferenciar rutas /api/* (404 JSON) del SPA fallback (index.html).
});
