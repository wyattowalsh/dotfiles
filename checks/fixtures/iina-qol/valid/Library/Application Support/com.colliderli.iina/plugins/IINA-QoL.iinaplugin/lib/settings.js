"use strict";

// Node-testable schema v4 validate/migrate. Keep rules in sync with main.js.

const SCHEMA_VERSION = 4;

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

function clamp(value, minimum, maximum) {
  return Math.min(Math.max(value, minimum), maximum);
}

function cloneDefaults() {
  const copy = {};
  Object.keys(DEFAULTS).forEach((key) => {
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

  // v3 minZoom (log2) is ignored; floor is always 100%.
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

module.exports = {
  SCHEMA_VERSION,
  DEFAULTS,
  BOOL_KEYS,
  NUMBER_SPECS,
  cloneDefaults,
  validate,
  migrateLegacy,
  migrate,
  hasLegacyLogZoom,
};
