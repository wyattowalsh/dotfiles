local M = {}

-- Source default is on after live cursor-zoom acceptance.
local tapEnabled = true
-- consume only cmd+shift scroll
local function pokePointer()
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseDown, {x=0,y=0})
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
