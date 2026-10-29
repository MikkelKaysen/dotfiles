-- Picker wrapper (ported from LazyVim's util/pick), hardcoded to Snacks.
-- `pick("files")` opens the picker in the workspace root unless opts.root == false.
local M = setmetatable({}, {
  __call = function(m, ...)
    return m.wrap(...)
  end,
})

M.picker = {
  name = "snacks",
  commands = {
    files = "files",
    live_grep = "grep",
    oldfiles = "recent",
  },
  open = function(source, opts)
    return Snacks.picker.pick(source, opts)
  end,
}

---@param command? string
---@param opts? {root?:boolean, cwd?:string, buf?:number}
function M.open(command, opts)
  command = command ~= "auto" and command or "files"
  opts = vim.deepcopy(opts or {})

  if not opts.cwd and opts.root ~= false then
    opts.cwd = require("util.root").get({ buf = opts.buf })
  end

  command = M.picker.commands[command] or command
  M.picker.open(command, opts)
end

---@param command? string
---@param opts? table
function M.wrap(command, opts)
  opts = opts or {}
  return function()
    M.open(command, vim.deepcopy(opts))
  end
end

function M.config_files()
  return M.wrap("files", { cwd = vim.fn.stdpath("config") })
end

return M