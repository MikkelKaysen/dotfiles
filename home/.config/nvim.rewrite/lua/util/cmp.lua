-- Completion helpers (the luasnip parts of LazyVim's cmp actions).
local M = {}

-- Stop an active luasnip session (used by the global <esc> keymap)
function M.snippet_stop()
  if package.loaded.luasnip and require("luasnip").expand_or_jumpable() then
    require("luasnip").unlink_current()
    return true
  end
end

return M