"use strict";

const { core, event, input, menu, mpv, preferences } = iina;

const PLUGIN_VERSION = "4.0.0";
// OTHER_MOUSE keysCarryDirectionOnly — fixture contract strings for iina-config.sh

const SCHEMA_VERSION = 4;
const EPSILON        = 1e-9;
const MIN_PERCENT    = 100;
const MAX_PERCENT    = 1000;
const LOG2_MAX       = Math.log2(10);
const UNAVAILABLE    = "zoom unavailable";
const HINT_TEXT      = "Cmd+Shift+scroll zooms at the pointer";

const DEFAULTS = {
  schemaVersion     : 4,
  cursorCentric     : true,
  showOSD           : true,
  resetOnFile       : true,
  invertScroll      : false,
  scrollSensitivity : 1.0,
  discreteStep      : 0.125,
  continuousStep    : 0.02,
  keyboardStep      : 0.125,
  minZoomPercent    : 100,
  maxZoomPercent    : 1000,
  detentPercent     : 105,
  panStep           : 0.1,
  mkvSubtitleCompat : false,
  hintVersion       : 0,
};

const BOOL_KEYS = [
  "cursorCentric",
  "showOSD",
  "resetOnFile",
  "invertScroll",
  "mkvSubtitleCompat",
];

const NUMBER_SPECS = {
  scrollSensitivity : { min: 0.25,  max: 4,    integer: false, fallback: 1.0 },
  discreteStep      : { min: 0.025, max: 0.5,  integer: false, fallback: 0.125 },
  continuousStep    : { min: 0.005, max: 0.2,  integer: false, fallback: 0.02 },
  keyboardStep      : { min: 0.025, max: 0.5,  integer: false, fallback: 0.125 },
  minZoomPercent    : { min: 100,   max: 1000, integer: true,  fallback: 100 },
  maxZoomPercent    : { min: 100,   max: 1000, integer: true,  fallback: 1000 },
  detentPercent     : { min: 100,   max: 1000, integer: true,  fallback: 105 },
  panStep           : { min: 0.025, max: 0.5,  integer: false, fallback: 0.1 },
  hintVersion       : { min: 0,     max: 1000, integer: true,  fallback: 0 },
};

const V4_KEYS = Object.keys(DEFAULTS);
const LEGACY_KEYS = ["minZoom", "maxZoom"];

let osdTimer = null;

// --- zoom math (keep in sync with lib/zoom.js) ---

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

// --- settings (keep in sync with lib/settings.js) ---

function cloneDefaults() {
  const copy = {};
  V4_KEYS.forEach((key) => {
    copy[key] = DEFAULTS[key];
  });
  return copy;
}

function readBool(raw, key) {
  return typeof raw[key] === "boolean" ? raw[key] : DEFAULTS[key];
}

function readNumber(raw, key) {
  const spec  = NUMBER_SPECS[key];
  const value = Number(raw[key]);
  if (!spec || !Number.isFinite(value)) {
    return spec ? spec.fallback : DEFAULTS[key];
  }
  const clamped = clamp(value, spec.min, spec.max);
  return spec.integer ? Math.round(clamped) : clamped;
}

function validate(raw) {
  const source = raw && typeof raw === "object" ? raw : {};
  const next   = cloneDefaults();
  BOOL_KEYS.forEach((key) => {
    next[key] = readBool(source, key);
  });
  Object.keys(NUMBER_SPECS).forEach((key) => {
    next[key] = readNumber(source, key);
  });
  if (next.minZoomPercent > next.maxZoomPercent) {
    next.minZoomPercent = DEFAULTS.minZoomPercent;
    next.maxZoomPercent = DEFAULTS.maxZoomPercent;
  }
  if (next.detentPercent < next.minZoomPercent) {
    next.detentPercent = next.minZoomPercent;
  }
  if (next.detentPercent > next.maxZoomPercent) {
    next.detentPercent = next.maxZoomPercent;
  }
  next.schemaVersion = SCHEMA_VERSION;
  return next;
}

function migrateLegacy(raw) {
  const source = raw && typeof raw === "object" ? raw : {};
  const next   = cloneDefaults();

  BOOL_KEYS.forEach((key) => {
    if (typeof source[key] === "boolean") {
      next[key] = source[key];
    }
  });

  ["scrollSensitivity", "discreteStep", "keyboardStep", "panStep", "detentPercent"].forEach((key) => {
    const value = Number(source[key]);
    if (Number.isFinite(value)) {
      next[key] = value;
    }
  });

  next.minZoomPercent = 100;
  if (Number.isFinite(Number(source.minZoomPercent)) && Number(source.minZoomPercent) >= 100) {
    next.minZoomPercent = Number(source.minZoomPercent);
  }

  if (Number.isFinite(Number(source.maxZoomPercent))) {
    next.maxZoomPercent = Number(source.maxZoomPercent);
  } else if (typeof source.maxZoom === "number" && Number.isFinite(source.maxZoom)) {
    if (Math.abs(source.maxZoom - 3) < 1e-9) {
      next.maxZoomPercent = 1000;
    } else {
      next.maxZoomPercent = clamp(Math.round(100 * Math.pow(2, source.maxZoom)), 100, 1000);
    }
  }

  const continuous = Number(source.continuousStep);
  if (Number.isFinite(continuous)) {
    next.continuousStep = Math.abs(continuous - 0.04) < 1e-9 ? 0.02 : continuous;
  }

  if (Number.isFinite(Number(source.hintVersion))) {
    next.hintVersion = Number(source.hintVersion);
  } else {
    next.hintVersion = 0;
  }

  next.schemaVersion = SCHEMA_VERSION;
  return next;
}

function hasLegacyLogZoom(raw) {
  return typeof raw.minZoom === "number" || typeof raw.maxZoom === "number";
}

function migrate(raw) {
  if (!raw || typeof raw !== "object") {
    return { settings: cloneDefaults(), persist: true, reason: "empty" };
  }
  const version = Number(raw.schemaVersion);
  if (Number.isFinite(version) && version > SCHEMA_VERSION) {
    return { settings: cloneDefaults(), persist: false, reason: "future" };
  }
  if (version === SCHEMA_VERSION && !hasLegacyLogZoom(raw)) {
    return { settings: validate(raw), persist: false, reason: "current" };
  }
  return { settings: validate(migrateLegacy(raw)), persist: true, reason: "legacy" };
}

function readRaw() {
  const raw = {};
  V4_KEYS.forEach((key) => {
    raw[key] = preferences.get(key);
  });
  LEGACY_KEYS.forEach((key) => {
    raw[key] = preferences.get(key);
  });
  return raw;
}

function currentSettings() {
  return migrate(readRaw()).settings;
}

function persistSettings(settings) {
  V4_KEYS.forEach((key) => {
    preferences.set(key, settings[key]);
  });
}

function clearLegacyLogKeys(raw) {
  if (typeof raw.minZoom === "number") {
    preferences.set("minZoom", false);
  }
  if (typeof raw.maxZoom === "number") {
    preferences.set("maxZoom", false);
  }
}

// --- mpv helpers ---

function finite(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function safeGetNumber(name, fallback) {
  try {
    return finite(mpv.getNumber(name), fallback);
  } catch (_) {
    return fallback;
  }
}

function safeGetNative(name) {
  try {
    return mpv.getNative(name);
  } catch (_) {
    return null;
  }
}

function safeSet(name, value) {
  try {
    mpv.set(name, value);
    return true;
  } catch (_) {
    return false;
  }
}

function showUnavailable() {
  try {
    core.osd(UNAVAILABLE);
  } catch (_) {}
}

function showZoomOSD() {
  if (!currentSettings().showOSD) {
    return;
  }
  if (osdTimer !== null) {
    clearTimeout(osdTimer);
  }
  osdTimer = setTimeout(() => {
    osdTimer = null;
    const zoom = safeGetNumber("video-zoom", 0);
    const percentage = Math.round(percentFromLog2(zoom));
    core.osd("Zoom " + percentage + "%");
  }, 45);
}

let lastPointer = null;
let lastMpvPointer = null;

function readOsdDimensions() {
  const dim = safeGetNative("osd-dimensions");
  if (!geometryIsUsable(dim)) {
    return null;
  }
  return {
    w  : Number(dim.w),
    h  : Number(dim.h),
    ml : Number.isFinite(Number(dim.ml)) ? Number(dim.ml) : 0,
    mr : Number.isFinite(Number(dim.mr)) ? Number(dim.mr) : 0,
    mt : Number.isFinite(Number(dim.mt)) ? Number(dim.mt) : 0,
    mb : Number.isFinite(Number(dim.mb)) ? Number(dim.mb) : 0,
  };
}

function rememberPointer(data) {
  const x = Number(data && data.x);
  const y = Number(data && data.y);
  if (!Number.isFinite(x) || !Number.isFinite(y)) {
    return;
  }
  lastPointer = { x: x, y: y };
}

// IINA key/mouse callbacks use AppKit window coords (origin bottom-left).
// mpv osd-dimensions / mouse-pos use origin top-left.
function pointerFromWindow(data, dim) {
  const x = Number(data && data.x);
  const y = Number(data && data.y);
  if (!Number.isFinite(x) || !Number.isFinite(y) || !dim) {
    return null;
  }
  const osdX = x;
  const osdY = dim.h - y;
  const left   = dim.ml;
  const right  = dim.w - dim.mr;
  const top    = dim.mt;
  const bottom = dim.h - dim.mb;
  const inside = osdX >= left && osdX <= right && osdY >= top && osdY <= bottom;
  return {
    x     : osdX,
    y     : osdY,
    hover : inside,
  };
}

function resolveAnchor(eventData) {
  const dim = readOsdDimensions();
  if (!dim) {
    return null;
  }
  // IINA documents key/mouse callback x,y as the current cursor in the
  // player window (AppKit, origin bottom-left). That is player-space
  // pointer, not a Hammerspoon-encoded payload. Synthetic F-keys with
  // location (0,0) are treated as missing.
  const ex = Number(eventData && eventData.x);
  const ey = Number(eventData && eventData.y);
  const hasEvent = Number.isFinite(ex) && Number.isFinite(ey)
    && !(ex === 0 && ey === 0);
  if (hasEvent) {
    const mouse = pointerFromWindow(eventData, dim);
    if (cursorIsUsable(mouse, dim)) {
      return { mouse: mouse, dim: dim };
    }
  }
  if (lastPointer) {
    const cached = pointerFromWindow(lastPointer, dim);
    if (cursorIsUsable(cached, dim)) {
      return { mouse: cached, dim: dim };
    }
  }
  const mpvMouse = safeGetNative("mouse-pos");
  if (cursorIsUsable(mpvMouse, dim)) {
    return {
      mouse: {
        x     : Number(mpvMouse.x),
        y     : Number(mpvMouse.y),
        hover : mpvMouse.hover === true,
      },
      dim: dim,
    };
  }
  if (cursorIsUsable(lastMpvPointer, dim)) {
    return { mouse: lastMpvPointer, dim: dim };
  }
  return null;
}

function resetView(showFeedback) {
  safeSet("video-zoom", 0);
  safeSet("video-pan-x", 0);
  safeSet("video-pan-y", 0);
  safeSet("video-align-x", 0);
  safeSet("video-align-y", 0);
  safeSet("panscan", 0);
  if (showFeedback && currentSettings().showOSD) {
    core.osd("Zoom reset to 100%");
  }
}

function snapshotView() {
  return {
    zoom   : safeGetNumber("video-zoom", 0),
    panX   : safeGetNumber("video-pan-x", 0),
    panY   : safeGetNumber("video-pan-y", 0),
    alignX : safeGetNumber("video-align-x", 0),
    alignY : safeGetNumber("video-align-y", 0),
    panscan: safeGetNumber("panscan", 0),
  };
}

function restoreView(snap) {
  if (!snap) {
    return;
  }
  safeSet("video-zoom", snap.zoom);
  safeSet("video-pan-x", snap.panX);
  safeSet("video-pan-y", snap.panY);
  safeSet("video-align-x", snap.alignX);
  safeSet("video-align-y", snap.alignY);
  safeSet("panscan", snap.panscan);
}

function zoomBy(deltaLog2, eventData) {
  const settings = currentSettings();
  const anchor   = resolveAnchor(eventData);
  if (!anchor) {
    showUnavailable();
    return false;
  }
  const snap    = snapshotView();
  const newZoom = stepZoom(snap.zoom, deltaLog2, settings);
  if (!Number.isFinite(newZoom)) {
    showUnavailable();
    return false;
  }
  if (Math.abs(newZoom) < EPSILON) {
    resetView(false);
    showZoomOSD();
    return true;
  }
  const align = alignAfterZoom(snap.zoom, newZoom, snap.panX, snap.panY, anchor.mouse, anchor.dim);
  if (!align) {
    showUnavailable();
    return false;
  }
  if (!safeSet("video-zoom", newZoom)) {
    restoreView(snap);
    showUnavailable();
    return false;
  }
  if (!safeSet("video-align-x", align.alignX) || !safeSet("video-align-y", align.alignY)) {
    restoreView(snap);
    showUnavailable();
    return false;
  }
  showZoomOSD();
  return true;
}

function scrollDelta(kind, directionIn) {
  const settings = currentSettings();
  let direction  = directionIn;
  if (settings.invertScroll) {
    direction = -direction;
  }
  const step = kind === "continuous" ? settings.continuousStep : settings.discreteStep;
  return direction * step * settings.scrollSensitivity;
}

function pan(axis, direction) {
  const settings = currentSettings();
  const property = axis === "x" ? "video-pan-x" : "video-pan-y";
  const current  = safeGetNumber(property, 0);
  safeSet(property, clamp(current + direction * settings.panStep, -3, 3));
  if (settings.showOSD) {
    const labels = {
      "x:1"  : "Pan left",
      "x:-1" : "Pan right",
      "y:1"  : "Pan up",
      "y:-1" : "Pan down",
    };
    core.osd(labels[axis + ":" + direction] || "Pan");
  }
}

function runSelfTest(data) {
  const before = safeGetNumber("video-zoom", 0);
  const probe  = stepZoom(before, 0.03125, currentSettings());
  let target   = probe;
  if (Math.abs(target - before) < EPSILON) {
    target = stepZoom(before, -0.03125, currentSettings());
  }
  safeSet("video-zoom", target);
  const observed = safeGetNumber("video-zoom", Number.NaN);
  safeSet("video-zoom", before);
  const passed = Number.isFinite(observed) && Math.abs(observed - target) < 0.001;
  const dim = readOsdDimensions();
  const mpvMouse = safeGetNative("mouse-pos") || {};
  const evX = Number(data && data.x);
  const ey = Number(data && data.y);
  const status = passed ? "IINA QoL self-test passed" : "IINA QoL self-test failed";
  const coords = " ev=" + evX + "," + ey
    + " mpv=" + mpvMouse.x + "," + mpvMouse.y + ",h=" + mpvMouse.hover
    + (dim ? (" osd=" + dim.w + "x" + dim.h) : "");
  try {
    core.osd(status + coords);
  } catch (_) {}
  return passed;
}

function maybeHint() {
  const raw      = readRaw();
  const settings = migrate(raw).settings;
  if (settings.hintVersion >= SCHEMA_VERSION) {
    return;
  }
  preferences.set("hintVersion", SCHEMA_VERSION);
  preferences.sync();
  setTimeout(() => {
    try {
      core.osd(HINT_TEXT);
    } catch (_) {}
  }, 350);
}

function bindHigh(keys, handler) {
  keys.forEach((key) => {
    input.onKeyDown(
      key,
      (data) => {
        try {
          handler(data);
        } catch (_) {
          showUnavailable();
        }
        return true;
      },
      input.PRIORITY_HIGH,
    );
  });
}

function privateKeys(base) {
  return [base, "Meta+" + base, "Shift+Meta+" + base];
}


function installPluginMenu() {
  try {
    menu.addItem(menu.item("Zoom In", () => {
      try {
        zoomBy(currentSettings().keyboardStep, lastPointer);
      } catch (_) {
        showUnavailable();
      }
    }, { keyBinding: "Shift+Meta+=" }));
    menu.addItem(menu.item("Zoom Out", () => {
      try {
        zoomBy(-currentSettings().keyboardStep, lastPointer);
      } catch (_) {
        showUnavailable();
      }
    }, { keyBinding: "Shift+Meta+-" }));
    menu.addItem(menu.item("Reset Zoom and Pan", () => {
      try {
        resetView(true);
      } catch (_) {}
    }, { keyBinding: "Shift+Meta+0" }));
    menu.addItem(menu.separator());
    menu.addItem(menu.item("Run Self-Test", () => {
      try {
        runSelfTest();
      } catch (_) {
        try {
          core.osd("IINA QoL self-test failed");
        } catch (__) {}
      }
    }, {}));
    menu.forceUpdate();
  } catch (_) {}
}

function start() {
  const raw    = readRaw();
  const result = migrate(raw);
  if (result.persist) {
    persistSettings(result.settings);
    clearLegacyLogKeys(raw);
    preferences.sync();
  }

  try {
    event.on("mpv.mouse-pos.changed", (pos) => {
      const dim = readOsdDimensions();
      if (cursorIsUsable(pos, dim)) {
        lastMpvPointer = {
          x     : Number(pos.x),
          y     : Number(pos.y),
          hover : true,
        };
      } else if (pos && pos.hover !== true) {
        lastMpvPointer = null;
      }
    });
  } catch (_) {}

  input.onMouseDown(input.MOUSE, (data) => {
    rememberPointer(data);
    return false;
  }, input.PRIORITY_LOW);
  input.onMouseDrag(input.MOUSE, (data) => {
    rememberPointer(data);
    return false;
  }, input.PRIORITY_LOW);
  input.onMouseUp(input.MOUSE, (data) => {
    rememberPointer(data);
    return false;
  }, input.PRIORITY_LOW);

  bindHigh(privateKeys("F15"), (data) => {
    runSelfTest(data);
  });
  bindHigh(privateKeys("F16"), () => {
    resetView(true);
  });
  bindHigh(privateKeys("F17"), (data) => {
    zoomBy(scrollDelta("discrete", 1), data);
  });
  bindHigh(privateKeys("F18"), (data) => {
    zoomBy(scrollDelta("discrete", -1), data);
  });
  bindHigh(privateKeys("F19"), (data) => {
    zoomBy(scrollDelta("continuous", 1), data);
  });
  bindHigh(privateKeys("F20"), (data) => {
    zoomBy(scrollDelta("continuous", -1), data);
  });

  bindHigh(["Shift+Meta+=", "Shift+Meta+PLUS"], (data) => {
    zoomBy(currentSettings().keyboardStep, data);
  });
  bindHigh(["Shift+Meta+-"], (data) => {
    zoomBy(-currentSettings().keyboardStep, data);
  });
  bindHigh(["Shift+Meta+0"], () => {
    resetView(true);
  });
  bindHigh(["Alt+Meta+LEFT"], () => {
    pan("x", 1);
  });
  bindHigh(["Alt+Meta+RIGHT"], () => {
    pan("x", -1);
  });
  bindHigh(["Alt+Meta+UP"], () => {
    pan("y", 1);
  });
  bindHigh(["Alt+Meta+DOWN"], () => {
    pan("y", -1);
  });

  // Menu APIs must not run during plugin load: IINA 1.4.4 updatePluginMenu
  // → forceUpdate is a recursive libdispatch lock (SIGTRAP).
  setTimeout(installPluginMenu, 0);

  mpv.addHook("on_load", 20, (next) => {
    try {
      if (currentSettings().mkvSubtitleCompat) {
        safeSet("demuxer-mkv-subtitle-preroll", "yes");
      }
    } catch (_) {}
    if (typeof next === "function") {
      next();
    }
  });

  event.on("iina.file-loaded", () => {
    try {
      if (currentSettings().resetOnFile) {
        resetView(false);
      }
      maybeHint();
    } catch (_) {}
  });
}

start();
