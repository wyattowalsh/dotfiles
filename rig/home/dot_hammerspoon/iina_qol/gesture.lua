-- Trackpad (continuous) vs mouse-wheel (discrete) zoom accumulator.
-- Invert is owned by the IINA plugin; this module emits raw direction only.

local M = {}

local THRESHOLD    = 10.0
local MAX_FLUSH    = 4
local WATCHDOG_SEC = 0.75

local PHASE_BEGAN     = 1
local PHASE_ENDED     = 4
local PHASE_CANCELLED = 8
local MOM_END         = 3

local st = {
  mode       = "idle", -- idle | ours | ignore
  acc        = 0,
  continuous = false,
  lastAt     = 0,
}

local function clock(now)
  if type(now) == "number" then
    return now
  end
  return hs.timer.secondsSinceEpoch()
end

function M.reset()
  st.mode       = "idle"
  st.acc        = 0
  st.continuous = false
  st.lastAt     = 0
end

function M.cancel()
  M.reset()
end

function M.isOurs()
  return st.mode == "ours"
end

local function empty(accept, first)
  return {
    accept = accept == true,
    first  = first == true,
    events = {},
  }
end

local function flushContinuous()
  local events = {}
  local n      = 0
  while math.abs(st.acc) >= THRESHOLD and n < MAX_FLUSH do
    local direction = st.acc > 0 and 1 or -1
    events[#events + 1] = {
      direction  = direction,
      continuous = true,
    }
    st.acc = st.acc - direction * THRESHOLD
    n      = n + 1
  end
  return events
end

--- Ingest one scroll sample.
--- sample: vertical, horizontal, continuous, phase, momentum, exactChord, now
--- returns { accept, first, events = { { direction, continuous }, ... } }
function M.ingest(sample)
  sample = sample or {}
  local now        = clock(sample.now)
  local vertical   = tonumber(sample.vertical) or 0
  local horizontal = tonumber(sample.horizontal) or 0
  local phase      = tonumber(sample.phase) or 0
  local momentum   = tonumber(sample.momentum) or 0
  local continuous = sample.continuous == true
  local exact      = sample.exactChord == true

  if st.mode ~= "idle" and (now - st.lastAt) > WATCHDOG_SEC then
    M.reset()
  end

  local phaseLess = phase == 0
  local began     = phase == PHASE_BEGAN
  local ended     = phase == PHASE_ENDED or momentum == MOM_END
  local cancelled = phase == PHASE_CANCELLED

  if cancelled then
    local wasOurs = st.mode == "ours"
    M.reset()
    return empty(wasOurs, false)
  end

  if st.mode == "ignore" then
    if ended then
      M.reset()
    else
      st.lastAt = now
    end
    return empty(false, false)
  end

  if st.mode == "idle" then
    local canBegin = began or (phaseLess and vertical ~= 0)
    if not canBegin then
      return empty(false, false)
    end
    -- A trackpad gesture that began without the chord is never hijacked.
    if began and not exact then
      st.mode   = "ignore"
      st.lastAt = now
      return empty(false, false)
    end
    local verticalDominant = math.abs(vertical) > math.abs(horizontal)
    if not exact or not verticalDominant then
      return empty(false, false)
    end
    st.mode       = "ours"
    st.continuous = continuous
    st.acc        = 0
    st.lastAt     = now
    local events
    if st.continuous then
      st.acc = vertical
      events = flushContinuous()
    else
      events = {
        {
          direction  = vertical > 0 and 1 or -1,
          continuous = false,
        },
      }
    end
    return {
      accept = true,
      first  = true,
      events = events,
    }
  end

  -- Latched ours: keep device class + consume through chord release / momentum.
  st.lastAt = now
  if ended then
    M.reset()
    return empty(true, false)
  end

  local events
  if st.continuous then
    st.acc = st.acc + vertical
    events = flushContinuous()
  elseif vertical == 0 then
    events = {}
  else
    events = {
      {
        direction  = vertical > 0 and 1 or -1,
        continuous = false,
      },
    }
  end
  return {
    accept = true,
    first  = false,
    events = events,
  }
end

return M
