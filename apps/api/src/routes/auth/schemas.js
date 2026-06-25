'use strict';

const loginSchema = {
    schema: {
        body: {
            type: 'object',
            required: ['login', 'password'],
            properties: {
                login: { type: 'string', minLength: 1 },
                password: { type: 'string', minLength: 1 },
            },
            additionalProperties: false,
        },
    },
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
};

const refreshSchema = {
    schema: {
        body: {
            type: 'object',
            required: ['refreshToken'],
            properties: {
                refreshToken: { type: 'string' },
            },
        },
    },
};

const logoutSchema = {
    schema: {
        body: {
            type: 'object',
            required: ['refreshToken'],
            properties: {
                refreshToken: { type: 'string' },
            },
        },
    },
};

module.exports = { loginSchema, refreshSchema, logoutSchema };
