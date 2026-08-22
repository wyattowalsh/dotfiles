"use strict";

// Node-testable zoom math. Keep formulas in sync with main.js.
// mpv video-zoom is log2(scale): 100% => 0, 1000% => log2(10).

const EPSILON     = 1e-9;
const MIN_PERCENT = 100;
const MAX_PERCENT = 1000;
const LOG2_MAX    = Math.log2(10);

function percentFromLog2(zoom) {
  return 100 * Math.pow(2, zoom);
}

function log2FromPercent(percent) {
  const value = Number(percent);
  if (!Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return Math.log2(value / 100);
}

function clamp(value, minimum, maximum) {
  return Math.min(Math.max(value, minimum), maximum);
}

function clampPercent(percent, minimum, maximum) {
  const minP = Number.isFinite(Number(minimum)) ? Number(minimum) : MIN_PERCENT;
  const maxP = Number.isFinite(Number(maximum)) ? Number(maximum) : MAX_PERCENT;
  return clamp(Number(percent), minP, maxP);
}

function clampLog2(zoom) {
  return clamp(Number(zoom), 0, LOG2_MAX);
}

function applyOutwardDetent(oldPercent, newPercent, minPercent, detentPercent) {
  const oldP    = Number(oldPercent);
  const nextP   = Number(newPercent);
  const minP    = Number.isFinite(Number(minPercent)) ? Number(minPercent) : MIN_PERCENT;
  const detentP = Number.isFinite(Number(detentPercent)) ? Number(detentPercent) : minP;
  if (nextP < oldP - EPSILON && nextP > minP && nextP <= detentP) {
    return minP;
  }
  return nextP;
}

function geometryIsUsable(dim) {
  if (!dim || typeof dim !== "object") {
    return false;
  }
  const width  = Number(dim.w);
  const height = Number(dim.h);
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
    return false;
  }
  const marginLeft   = Number.isFinite(Number(dim.ml)) ? Number(dim.ml) : 0;
  const marginRight  = Number.isFinite(Number(dim.mr)) ? Number(dim.mr) : 0;
  const marginTop    = Number.isFinite(Number(dim.mt)) ? Number(dim.mt) : 0;
  const marginBottom = Number.isFinite(Number(dim.mb)) ? Number(dim.mb) : 0;
  const videoW = width  - marginLeft  - marginRight;
  const videoH = height - marginTop   - marginBottom;
  return Number.isFinite(videoW) && Number.isFinite(videoH)
    && Math.abs(videoW) > EPSILON && Math.abs(videoH) > EPSILON;
}

function cursorIsUsable(mouse, dim) {
  if (!mouse || typeof mouse !== "object") {
    return false;
  }
  if (mouse.hover !== true) {
    return false;
  }
  const x = Number(mouse.x);
  const y = Number(mouse.y);
  if (!Number.isFinite(x) || !Number.isFinite(y)) {
    return false;
  }
  // libmpv reports {0,0} before any real hover; that is not a pointer.
  if (Math.abs(x) < EPSILON && Math.abs(y) < EPSILON) {
    return false;
  }
  return geometryIsUsable(dim);
}

function stepZoom(oldZoom, deltaLog2, settings) {
  const minP    = settings && Number.isFinite(Number(settings.minZoomPercent))
    ? Number(settings.minZoomPercent) : MIN_PERCENT;
  const maxP    = settings && Number.isFinite(Number(settings.maxZoomPercent))
    ? Number(settings.maxZoomPercent) : MAX_PERCENT;
  const detentP = settings && Number.isFinite(Number(settings.detentPercent))
    ? Number(settings.detentPercent) : minP;
  const oldPercent = percentFromLog2(Number(oldZoom) || 0);
  let nextPercent  = percentFromLog2((Number(oldZoom) || 0) + Number(deltaLog2));
  nextPercent = clampPercent(nextPercent, minP, maxP);
  nextPercent = applyOutwardDetent(oldPercent, nextPercent, minP, detentP);
  nextPercent = clampPercent(nextPercent, minP, maxP);
  return clampLog2(log2FromPercent(nextPercent));
}

function panAfterZoom(oldZoom, newZoom, panX, panY, mouse, dim) {
  // Kept as a pan-space helper; cursor zoom uses alignAfterZoom (mpv positioning.lua).
  if (!cursorIsUsable(mouse, dim)) {
    return null;
  }
  const factor = Math.pow(2, Number(newZoom) - Number(oldZoom));
  if (!Number.isFinite(factor) || Math.abs(factor) < EPSILON) {
    return { panX: Number(panX) || 0, panY: Number(panY) || 0 };
  }
  const marginLeft   = Number.isFinite(Number(dim.ml)) ? Number(dim.ml) : 0;
  const marginRight  = Number.isFinite(Number(dim.mr)) ? Number(dim.mr) : 0;
  const marginTop    = Number.isFinite(Number(dim.mt)) ? Number(dim.mt) : 0;
  const marginBottom = Number.isFinite(Number(dim.mb)) ? Number(dim.mb) : 0;
  const videoW = Number(dim.w) - marginLeft - marginRight;
  const videoH = Number(dim.h) - marginTop  - marginBottom;
  const mx = Number(mouse.x) - Number(dim.w) / 2;
  const my = Number(mouse.y) - Number(dim.h) / 2;
  const nextPanX = (Number(panX) || 0) + (mx / videoW) * (1 / factor - 1);
  const nextPanY = (Number(panY) || 0) + (my / videoH) * (1 / factor - 1);
  if (!Number.isFinite(nextPanX) || !Number.isFinite(nextPanY)) {
    return null;
  }
  return {
    panX: clamp(nextPanX, -3, 3),
    panY: clamp(nextPanY, -3, 3),
  };
}

// Port of mpv player/lua/positioning.lua cursor-centric-zoom (video-align, pre-zoom osd-dimensions).
function alignAfterZoom(oldZoom, newZoom, panX, panY, mouse, dim) {
  if (!cursorIsUsable(mouse, dim)) {
    return null;
  }
  const amount = Number(newZoom) - Number(oldZoom);
  const factor = Math.pow(2, amount);
  if (!Number.isFinite(factor) || Math.abs(factor) < EPSILON) {
    return null;
  }
  const width  = (Number(dim.w) - Number(dim.ml) - Number(dim.mr)) * factor;
  const height = (Number(dim.h) - Number(dim.mt) - Number(dim.mb)) * factor;
  const denomX = Number(dim.w) - width;
  const denomY = Number(dim.h) - height;
  if (Math.abs(denomX) < EPSILON || Math.abs(denomY) < EPSILON) {
    return null;
  }
  const marginLeft = (Number(dim.ml) - Number(mouse.x)) * factor + Number(mouse.x);
  const marginTop  = (Number(dim.mt) - Number(mouse.y)) * factor + Number(mouse.y);
  const alignX = 2 * (marginLeft - (Number(panX) || 0) * width)  / denomX - 1;
  const alignY = 2 * (marginTop  - (Number(panY) || 0) * height) / denomY - 1;
  if (!Number.isFinite(alignX) || !Number.isFinite(alignY)) {
    return null;
  }
  return {
    alignX: clamp(alignX, -1, 1),
    alignY: clamp(alignY, -1, 1),
  };
}

module.exports = {
  EPSILON,
  MIN_PERCENT,
  MAX_PERCENT,
  LOG2_MAX,
  percentFromLog2,
  log2FromPercent,
  clamp,
  clampPercent,
  clampLog2,
  applyOutwardDetent,
  geometryIsUsable,
  cursorIsUsable,
  stepZoom,
  panAfterZoom,
  alignAfterZoom,
};
