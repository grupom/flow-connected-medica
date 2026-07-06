'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// apps/api/src/routes/admin/boards/mediaService.js -> apps/api/media/boards
const MEDIA_ROOT = path.join(__dirname, '../../../../media/boards');

const VIDEO_MIME_EXT = { 'video/mp4': '.mp4' };
const IMAGE_MIME_EXT = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/webp': '.webp',
};

const MAX_VIDEO_BYTES = 100 * 1024 * 1024; // 100MB
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;   // 8MB per image
const MAX_IMAGES = 20;
const DEFAULT_IMAGE_DURATION_SECONDS = 5;

function boardMediaDir(boardId, kind) {
    // kind: 'video' | 'images'
    const dir = path.join(MEDIA_ROOT, String(boardId), kind);
    fs.mkdirSync(dir, { recursive: true });
    return dir;
}

function generateFilename(extension) {
    return `${Date.now()}-${crypto.randomBytes(4).toString('hex')}${extension}`;
}

// Wipes and recreates a board's media directory of a given kind.
// Errors are logged but not fatal — a file may already be gone if removed manually.
async function clearBoardMediaDir(boardId, kind, logger) {
    const dir = path.join(MEDIA_ROOT, String(boardId), kind);
    try {
        await fs.promises.rm(dir, { recursive: true, force: true });
    } catch (err) {
        logger?.warn({ err, dir }, 'Failed to clear board media directory');
    }
    fs.mkdirSync(dir, { recursive: true });
}

// Attaches ready-to-use ad_video_url / ad_images[].url fields to a display_boards
// row, derived from its stored filenames — keeps the /media/boards/... storage
// layout out of both the SQL layer and the frontend. Mutates and returns board.
function attachMediaUrls(board) {
    if (!board) return board;
    if (board.ad_media_type === 'video' && board.ad_video_filename) {
        board.ad_video_url = `/media/boards/${board.board_id}/video/${board.ad_video_filename}`;
    }
    if (Array.isArray(board.ad_images)) {
        board.ad_images = board.ad_images.map((img) => ({
            ...img,
            url: `/media/boards/${board.board_id}/images/${img.filename}`,
        }));
    }
    return board;
}

module.exports = {
    MEDIA_ROOT,
    VIDEO_MIME_EXT,
    IMAGE_MIME_EXT,
    MAX_VIDEO_BYTES,
    MAX_IMAGE_BYTES,
    MAX_IMAGES,
    DEFAULT_IMAGE_DURATION_SECONDS,
    boardMediaDir,
    generateFilename,
    clearBoardMediaDir,
    attachMediaUrls,
};
