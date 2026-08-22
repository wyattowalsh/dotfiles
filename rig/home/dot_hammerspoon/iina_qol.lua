-- IINA QoL Hammerspoon bridge: exact Command+Shift+scroll -> private F-keys.
-- Event tap defaults ON after live cursor-zoom acceptance.

local M = {}

M.BUNDLE_ID           = "com.colliderli.iina"
M.DEFAULT_TAP_ENABLED = true
M.URL_EVENT           = "iina-qol"

local KEY_DISCRETE_IN  = "f17"
local KEY_DISCRETE_OUT = "f18"
local KEY_SMOOTH_IN    = "f19"
local KEY_SMOOTH_OUT   = "f20"
local KEY_DOCTOR       = "f15"

local gesture = require("iina_qol.gesture")
local window  = require("iina_qol.window")

local types = hs.eventtap.event.types
local props = hs.eventtap.event.properties

local state = {
  tap       = nil,
  urlBound  = false,
  sessionOn = false,
}

local keyQueue   = {}
local flushArmed = false

local function isExactCmdShift(flags)
  -- Exact chord: Command+Shift only. alt/ctrl/fn (or a missing flag table) fail.
  return flags ~= nil
     and flags.cmd == true
     and flags.shift == true
     and flags.alt ~= true
     and flags.ctrl ~= true
     and flags.fn ~= true
end

local function axisValue(e, continuous, vertical)
  local property
  if continuous then
    property = vertical and props.scrollWheelEventPointDeltaAxis1
                        or  props.scrollWheelEventPointDeltaAxis2
  else
    property = vertical and props.scrollWheelEventFixedPtDeltaAxis1
                        or  props.scrollWheelEventFixedPtDeltaAxis2
  end
  local value = tonumber(e:getProperty(property)) or 0
  if value == 0 then
    property = vertical and props.scrollWheelEventDeltaAxis1
                        or  props.scrollWheelEventDeltaAxis2
    value    = tonumber(e:getProperty(property)) or 0
  end
  return value
end

local function zoomKey(direction, continuous)
  if continuous then
    return direction > 0 and KEY_SMOOTH_IN or KEY_SMOOTH_OUT
  end
  return direction > 0 and KEY_DISCRETE_IN or KEY_DISCRETE_OUT
end

local function sendKey(app, key)
  if not key then
    return
  end
  local loc = hs.mouse.absolutePosition()
  -- Posted-to-app key events often arrive in IINA with locationInWindow (0,0).
  -- A system-wide key after focus keeps NSEvent.locationInWindow at the cursor.
  -- mouseMoved wakes mpv mouse-pos/hover in the VO.
  local moved = hs.eventtap.event.newMouseEvent(types.mouseMoved, loc)
  moved:post()
  if app then
    moved:post(app)
  end
  local down = hs.eventtap.event.newKeyEvent({}, key, true)
  local up   = hs.eventtap.event.newKeyEvent({}, key, false)
  down:location(loc)
  up:location(loc)
  down:post()
  up:post()
end

local function flushKeys()
  flushArmed = false
  local batch = keyQueue
  keyQueue    = {}
  for i = 1, #batch do
    local item = batch[i]
    pcall(function()
      sendKey(item.app, item.key)
    end)
  end
end

local function enqueueKey(app, key)
  if not app or not key then
    return
  end
  keyQueue[#keyQueue + 1] = { app = app, key = key }
  if not flushArmed then
    flushArmed = true
    hs.timer.doAfter(0, flushKeys)
  end
end

local function sendDoctorKey(app)
  if not app then
    return
  end
  pcall(function()
    sendKey(app, KEY_DOCTOR)
  end)
end

local function tapShouldRun()
  return M.DEFAULT_TAP_ENABLED == true or state.sessionOn == true
end

local function handleScroll(e)
  local flags = e:getFlags()
  local exact = isExactCmdShift(flags)
  if not exact and not gesture.isOurs() then
    return false
  end

  local win, app = window.playerUnderPointer()
  if not win or not app then
    if gesture.isOurs() then
      gesture.cancel()
    end
    return false
  end

  local continuous = (tonumber(e:getProperty(props.scrollWheelEventIsContinuous)) or 0) ~= 0
  local vertical   = axisValue(e, continuous, true)
  local horizontal = axisValue(e, continuous, false)
  local phase      = tonumber(e:getProperty(props.scrollWheelEventScrollPhase)) or 0
  local momentum   = tonumber(e:getProperty(props.scrollWheelEventMomentumPhase)) or 0

  local result = gesture.ingest({
    vertical   = vertical,
    horizontal = horizontal,
    continuous = continuous,
    phase      = phase,
    momentum   = momentum,
    exactChord = exact,
  })

  if not result.accept then
    return false
  end

  if result.first then
    window.focusRaise(win)
  end

  for i = 1, #result.events do
    local ev = result.events[i]
    enqueueKey(app, zoomKey(ev.direction, ev.continuous))
  end
  return true
end

local function onScroll(e)
  local ok, consume = pcall(handleScroll, e)
  if not ok then
    if state.tap then
      state.tap:stop()
    end
    gesture.reset()
    print("iina_qol: tap stopped: " .. tostring(consume))
    return false
  end
  return consume == true
end

local function ensureTap()
  if not state.tap then
    state.tap = hs.eventtap.new({ types.scrollWheel }, onScroll)
  end
end

local function startTap()
  if not hs.accessibilityState() then
    hs.alert.show("IINA QoL: enable Hammerspoon Accessibility")
    return
  end
  ensureTap()
  if state.tap and not state.tap:isEnabled() then
    state.tap:start()
  end
end

local function stopTap()
  if state.tap then
    state.tap:stop()
  end
  gesture.reset()
  keyQueue   = {}
  flushArmed = false
end

local function bindUrl()
  if state.urlBound then
    return
  end
  hs.urlevent.bind(M.URL_EVENT, function(_, params)
    local action = (params and params.action) or "doctor"
    if action == "doctor" then
      M.doctor()
    elseif action == "enable" then
      M.enableSession()
    elseif action == "disable" then
      M.disableSession()
    elseif action == "reload" then
      hs.reload()
    end
  end)
  state.urlBound = true
end

function M.start()
  pcall(require, "hs.ipc")
  bindUrl()
  if tapShouldRun() then
    startTap()
  end
end

function M.stop()
  stopTap()
end

function M.enableSession()
  state.sessionOn = true
  bindUrl()
  startTap()
end

function M.disableSession()
  state.sessionOn = false
  stopTap()
end

function M.doctor()
  -- On-demand only: never write files from the scroll hot path.
  local tapOn = state.tap and state.tap:isEnabled() or false
  print(string.format(
    "iina_qol doctor tap=%s session=%s default=%s",
    tostring(tapOn),
    tostring(state.sessionOn),
    tostring(M.DEFAULT_TAP_ENABLED)
  ))
  local app = hs.application.get(M.BUNDLE_ID)
  if not app then
    hs.application.launchOrFocusByBundleID(M.BUNDLE_ID)
    hs.timer.doAfter(1.0, function()
      sendDoctorKey(hs.application.get(M.BUNDLE_ID))
    end)
    return
  end
  sendDoctorKey(app)
end

return M
