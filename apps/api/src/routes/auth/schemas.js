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

// refreshToken no longer travels in the body — it comes from the httpOnly
// cq_refresh_token cookie (see plugins/jwt.js + routes/auth/index.js). No body
// schema at all: the request is sent with no body/Content-Type, which Fastify
// leaves as `undefined` — a `{type:'object'}` schema would reject that.
const refreshSchema = {
    config: { rateLimit: { max: 20, timeWindow: '1 minute' } },
};

const logoutSchema = {
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
};

module.exports = { loginSchema, refreshSchema, logoutSchema };
