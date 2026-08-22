-- Locate a visible IINA player under the pointer (not merely the focused window).

local M = {}

M.BUNDLE_ID = "com.colliderli.iina"

local function containsPoint(frame, point)
  if not frame or not point then
    return false
  end
  local x = point.x
  local y = point.y
  return x >= frame.x
     and y >= frame.y
     and x < (frame.x + frame.w)
     and y < (frame.y + frame.h)
end

--- Topmost visible IINA window whose frame contains the pointer.
--- Returns `win, app` or nil.
function M.playerUnderPointer(point)
  point = point or hs.mouse.absolutePosition()
  if not point then
    return nil
  end
  local ordered = hs.window.orderedWindows()
  for i = 1, #ordered do
    local win = ordered[i]
    if win and not win:isMinimized() then
      local app = win:application()
      if app and app:bundleID() == M.BUNDLE_ID then
        if containsPoint(win:frame(), point) then
          return win, app
        end
      end
    end
  end
  return nil
end

--- Raise and focus the given IINA window. Ordinary scroll must never call this.
function M.focusRaise(win)
  if not win then
    return false
  end
  win:raise()
  win:focus()
  local loc = hs.mouse.absolutePosition()
  local moved = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, loc)
  moved:post()
  local app = win:application()
  if app then
    moved:post(app)
  end
  return true
end

return M
