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

local function matchIinaWindow(win, point)
  if not win or win:isMinimized() then
    return nil
  end
  local app = win:application()
  if not app or app:bundleID() ~= M.BUNDLE_ID then
    return nil
  end
  if point and not containsPoint(win:frame(), point) then
    return nil
  end
  return win, app
end

--- Topmost visible IINA window whose frame contains the pointer.
--- Falls back to IINA's own window list (PiP / non-standard AX windows are
--- often missing from hs.window.orderedWindows) and then the focused IINA
--- window when the pointer is still inside it.
--- Returns `win, app` or nil.
function M.playerUnderPointer(point)
  point = point or hs.mouse.absolutePosition()
  if not point then
    return nil
  end
  local ordered = hs.window.orderedWindows()
  for i = 1, #ordered do
    local win, app = matchIinaWindow(ordered[i], point)
    if win then
      return win, app
    end
  end
  local app = hs.application.get(M.BUNDLE_ID)
  if app then
    local wins = app:allWindows() or {}
    for i = 1, #wins do
      local win = matchIinaWindow(wins[i], point)
      if win then
        return win, app
      end
    end
    local focused = app:focusedWindow() or app:mainWindow()
    local win = matchIinaWindow(focused, point)
    if win then
      return win, app
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
