'use strict';

const { synthesize } = require('./service');

module.exports = async function ttsRoutes(fastify) {
    /**
     * GET /api/tts/announce?code=C01&station=Consultorio+1
     *
     * Public endpoint (no auth) — the board screen is public.
     * Returns a WAV audio stream of the announcement.
     * Responses are cached on disk; repeated calls for the same
     * code+station are served instantly.
     */
    fastify.get('/announce', {
        schema: {
            querystring: {
                type: 'object',
                required: ['code'],
                properties: {
                    code:    { type: 'string', minLength: 1, maxLength: 20 },
                    station: { type: 'string', maxLength: 120, default: '' },
                    prefix:  { type: 'string', maxLength: 20,  default: '' },
                },
            },
        },
    }, async (request, reply) => {
        const { code, station = '', prefix = '' } = request.query;
        try {
            const stream = await synthesize(code, station, prefix);
            return reply
                .header('Content-Type', 'audio/wav')
                .header('Cache-Control', 'public, max-age=86400')
                .send(stream);
        } catch (err) {
            const status = err.statusCode || 500;
            request.log.error({ err }, 'TTS synthesis failed');
            return reply.code(status).send({ error: err.message });
        }
    });
};
