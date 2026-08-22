-- >>> IINA QOL >>>
pcall(require, "hs.ipc")
local okIinaQol, iinaQol = pcall(require, "iina_qol")
if okIinaQol and iinaQol then
  iinaQol.start()
else
  print("IINA QoL load error: " .. tostring(iinaQol))
end
-- <<< IINA QOL <<<
