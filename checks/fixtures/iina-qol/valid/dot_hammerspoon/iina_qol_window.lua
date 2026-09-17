local M = {}

function M.playerUnderPointer()
  -- orderedWindows misses PiP; production falls back to allWindows.
  return nil
end

return M
