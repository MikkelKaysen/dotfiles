-- 'statuscolumn' provider (LazyVim used snacks' statuscolumn here too).
local M = {}

function M.get()
  return package.loaded.snacks and require("snacks.statuscolumn").get() or ""
end

return M