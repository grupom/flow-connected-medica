'use strict';

const fs = require('fs');
const path = require('path');
const { pipeline } = require('stream/promises');

const { query } = require('../../../db/pool');
const {
    VIDEO_MIME_EXT,
    IMAGE_MIME_EXT,
    MAX_VIDEO_BYTES,
    MAX_IMAGE_BYTES,
    MAX_IMAGES,
    DEFAULT_IMAGE_DURATION_SECONDS,
    boardMediaDir,
    generateFilename,
    clearBoardMediaDir,
} = require('./mediaService');

async function getBoard(id) {
    const { rows } = await query(
        `SELECT board_id, ad_images FROM clinicqueue.display_boards WHERE board_id = $1`,
        [id]
    );
    return rows[0] || null;
}

module.exports = async function boardMediaRoutes(fastify) {
    const adminOnly = {
        preHandler: [
            fastify.authenticate,
            async (request, reply) => {
                const roles = request.user?.role_codes ?? [];
                if (!roles.includes('ADMIN')) {
                    return reply.code(403).send({ error: 'Forbidden', message: 'Se requiere rol ADMIN' });
                }
            },
        ],
    };

    // POST /api/admin/boards/:id/media/video
    // Replaces the board's active ad campaign with a single mp4 video.
    fastify.post('/:id/media/video', {
        ...adminOnly,
        schema: { params: { type: 'object', properties: { id: { type: 'integer' } } } },
    }, async (request, reply) => {
        const { id } = request.params;
        const board = await getBoard(id);
        if (!board) return reply.code(404).send({ error: 'Not Found', message: 'Board not found' });

        const part = await request.file({ limits: { fileSize: MAX_VIDEO_BYTES } });
        if (!part) return reply.code(400).send({ error: 'Bad Request', message: 'No se recibió ningún archivo' });

        const ext = VIDEO_MIME_EXT[part.mimetype];
        if (!ext) {
            return reply.code(415).send({ error: 'Unsupported Media Type', message: 'Solo se acepta video/mp4' });
        }

        // Switching to video wipes any previous video AND any previous image sequence.
        await clearBoardMediaDir(id, 'video', request.log);
        await clearBoardMediaDir(id, 'images', request.log);

        const filename = generateFilename(ext);
        const destPath = path.join(boardMediaDir(id, 'video'), filename);

        try {
            await pipeline(part.file, fs.createWriteStream(destPath));
        } catch (err) {
            request.log.error({ err }, 'Video upload stream failed');
            return reply.code(500).send({ error: 'Internal Server Error', message: 'Falló al guardar el video' });
        }

        if (part.file.truncated) {
            await fs.promises.rm(destPath, { force: true });
            return reply.code(413).send({ error: 'Payload Too Large', message: 'El video excede el tamaño máximo permitido (100MB)' });
        }

        const { rows } = await query(
            `UPDATE clinicqueue.display_boards
       SET ad_media_type = 'video', ad_video_filename = $2, ad_images = '[]'::jsonb,
           ad_uploaded_at = now(), ad_uploaded_by = $3, ad_version = ad_version + 1
       WHERE board_id = $1
       RETURNING board_id, ad_media_type, ad_video_filename, ad_images, ad_version`,
            [id, filename, request.user.user_id]
        );
        return reply.send({ data: rows[0] });
    });

    // POST /api/admin/boards/:id/media/images
    // Replaces the board's active ad campaign with a sequence of images.
    // Non-file field "durations" (optional): JSON array of per-image seconds, aligned by upload order.
    fastify.post('/:id/media/images', {
        ...adminOnly,
        schema: { params: { type: 'object', properties: { id: { type: 'integer' } } } },
    }, async (request, reply) => {
        const { id } = request.params;
        const board = await getBoard(id);
        if (!board) return reply.code(404).send({ error: 'Not Found', message: 'Board not found' });

        // Switching to image sequence wipes any previous images AND any previous video.
        await clearBoardMediaDir(id, 'video', request.log);
        await clearBoardMediaDir(id, 'images', request.log);
        const dir = boardMediaDir(id, 'images');

        const filenames = [];
        let durations = null;

        for await (const part of request.parts({ limits: { fileSize: MAX_IMAGE_BYTES, files: MAX_IMAGES } })) {
            if (part.type === 'file') {
                const ext = IMAGE_MIME_EXT[part.mimetype];
                if (!ext) {
                    part.file.resume(); // drain to avoid hanging the request
                    return reply.code(415).send({ error: 'Unsupported Media Type', message: 'Solo se aceptan imágenes JPEG/PNG/WEBP' });
                }
                const filename = generateFilename(ext);
                await pipeline(part.file, fs.createWriteStream(path.join(dir, filename)));
                if (part.file.truncated) {
                    return reply.code(413).send({ error: 'Payload Too Large', message: 'Una imagen excede el tamaño máximo permitido (8MB)' });
                }
                filenames.push(filename);
            } else if (part.fieldname === 'durations') {
                try { durations = JSON.parse(part.value); } catch { durations = null; }
            }
        }

        if (!filenames.length) {
            return reply.code(400).send({ error: 'Bad Request', message: 'No se recibió ninguna imagen' });
        }

        const adImages = filenames.map((filename, i) => ({
            filename,
            duration_seconds: Number.isFinite(durations?.[i]) && durations[i] > 0
                ? durations[i]
                : DEFAULT_IMAGE_DURATION_SECONDS,
        }));

        const { rows } = await query(
            `UPDATE clinicqueue.display_boards
       SET ad_media_type = 'image_sequence', ad_video_filename = NULL, ad_images = $2::jsonb,
           ad_uploaded_at = now(), ad_uploaded_by = $3, ad_version = ad_version + 1
       WHERE board_id = $1
       RETURNING board_id, ad_media_type, ad_video_filename, ad_images, ad_version`,
            [id, JSON.stringify(adImages), request.user.user_id]
        );
        return reply.send({ data: rows[0] });
    });

    // PATCH /api/admin/boards/:id/media/images/order
    // Reorders/re-times an existing image sequence without re-uploading files.
    fastify.patch('/:id/media/images/order', {
        ...adminOnly,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: {
                type: 'object',
                required: ['images'],
                properties: {
                    images: {
                        type: 'array',
                        items: {
                            type: 'object',
                            required: ['filename', 'duration_seconds'],
                            properties: {
                                filename: { type: 'string' },
                                duration_seconds: { type: 'number', minimum: 1, maximum: 120 },
                            },
                        },
                    },
                },
            },
        },
    }, async (request, reply) => {
        const { id } = request.params;
        const board = await getBoard(id);
        if (!board) return reply.code(404).send({ error: 'Not Found', message: 'Board not found' });

        const existingFilenames = new Set((board.ad_images || []).map((img) => img.filename));
        const { images } = request.body;
        const allValid = images.every((img) => existingFilenames.has(img.filename));
        if (!allValid || images.length !== existingFilenames.size) {
            return reply.code(400).send({ error: 'Bad Request', message: 'La lista de imágenes no coincide con la secuencia actual' });
        }

        const { rows } = await query(
            `UPDATE clinicqueue.display_boards
       SET ad_images = $2::jsonb, ad_version = ad_version + 1
       WHERE board_id = $1
       RETURNING board_id, ad_media_type, ad_video_filename, ad_images, ad_version`,
            [id, JSON.stringify(images)]
        );
        return reply.send({ data: rows[0] });
    });

    // PATCH /api/admin/boards/:id/media/settings
    fastify.patch('/:id/media/settings', {
        ...adminOnly,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: {
                type: 'object',
                properties: {
                    ad_rotation_seconds: { type: 'integer', minimum: 3, maximum: 600 },
                    ad_interrupt_cooldown_seconds: { type: 'integer', minimum: 1, maximum: 120 },
                },
            },
        },
    }, async (request, reply) => {
        const { id } = request.params;
        const { ad_rotation_seconds, ad_interrupt_cooldown_seconds } = request.body;
        const { rows } = await query(
            `UPDATE clinicqueue.display_boards
       SET ad_rotation_seconds = COALESCE($2, ad_rotation_seconds),
           ad_interrupt_cooldown_seconds = COALESCE($3, ad_interrupt_cooldown_seconds)
       WHERE board_id = $1
       RETURNING board_id, ad_rotation_seconds, ad_interrupt_cooldown_seconds`,
            [id, ad_rotation_seconds ?? null, ad_interrupt_cooldown_seconds ?? null]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Board not found' });
        return reply.send({ data: rows[0] });
    });

    // DELETE /api/admin/boards/:id/media
    fastify.delete('/:id/media', {
        ...adminOnly,
        schema: { params: { type: 'object', properties: { id: { type: 'integer' } } } },
    }, async (request, reply) => {
        const { id } = request.params;
        const board = await getBoard(id);
        if (!board) return reply.code(404).send({ error: 'Not Found', message: 'Board not found' });

        await clearBoardMediaDir(id, 'video', request.log);
        await clearBoardMediaDir(id, 'images', request.log);

        const { rows } = await query(
            `UPDATE clinicqueue.display_boards
       SET ad_media_type = 'none', ad_video_filename = NULL, ad_images = '[]'::jsonb,
           ad_uploaded_at = NULL, ad_uploaded_by = NULL, ad_version = ad_version + 1
       WHERE board_id = $1
       RETURNING board_id, ad_media_type, ad_video_filename, ad_images, ad_version`,
            [id]
        );
        return reply.send({ data: rows[0] });
    });
};
