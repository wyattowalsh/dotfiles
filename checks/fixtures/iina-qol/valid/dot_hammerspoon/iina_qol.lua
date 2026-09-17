local M = {}

-- Source default is on after live cursor-zoom acceptance.
local tapEnabled = true
-- zoom chord: Command required, Shift optional
local function isZoomChord(flags)
  return flags ~= nil and flags.cmd == true
end
-- Scroll NSEvents omit cmd; merge hs.eventtap.checkKeyboardModifiers().
local function chordFlags(eventFlags)
  local held = hs.eventtap.checkKeyboardModifiers() or {}
  local flags = eventFlags or {}
  return { cmd = flags.cmd == true or held.cmd == true }
end
local function pokePointer()
  -- middleClickAction 4 is togglePIP; pin 0 (none) before this poke.
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseDown, {x=0,y=0})
end
-- orderedWindows misses PiP; fall back to application:allWindows().
local function playerUnderPointer()
  return nil
end
local function emitPan()
  return nil
end

function M.start()
  if not tapEnabled then
    return
  end
end

function M.stop()
end

function M.enableSession()
end

function M.disableSession()
end

return M
