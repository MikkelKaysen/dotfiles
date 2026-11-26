-- ---------------------------------------------------------------------------
-- trouble (ported from LazyVim's editor.lua).
-- NOTE: [q/]q are re-registered here so they win over config/keymaps.lua —
-- same ordering as LazyVim's lazy.nvim key registration.
-- ---------------------------------------------------------------------------

local function dedupe_lsp_locations(items)
  local seen = {}
  local filtered = {}

  for _, item in ipairs(items or {}) do
    if item then
      local filename = item.filename or (item.buf and vim.api.nvim_buf_get_name(item.buf)) or ""
      if type(filename) == "string" and filename ~= "" then
        filename = vim.fs.normalize(filename)
      end

      local pos = item.pos or { 1, 0 }
      local end_pos = item.end_pos or pos

      local start_line = tonumber(pos[1]) or 1
      local start_col = tonumber(pos[2]) or 0
      local end_line = tonumber(end_pos[1]) or start_line
      local end_col = tonumber(end_pos[2]) or start_col
      local key = table.concat({ filename, start_line, start_col, end_line, end_col }, "\x1f")

      if not seen[key] then
        seen[key] = true
        filtered[#filtered + 1] = item
      end
    end
  end

  return filtered
end

require("trouble").setup({
  modes = {
    lsp_base = {
      win = { type = "split", position = "right", size = 40 },
      focus = false,
      filter = dedupe_lsp_locations,
    },
    lsp = {
      win = { type = "split", position = "right", size = 40 },
      focus = false,
    },
    symbols = {
      win = { type = "split", position = "right", size = 40 },
      focus = false,
    },
  },
})

-- Sidebar helpers: `symbols` and `lsp` are independent views stacked in one
-- right-hand column (symbols on top, lsp below). Each toggles on its own.
local SIDEBAR_WIDTH = 40
local LSP_HEIGHT = 0.46

-- Returns the open view for `mode`, if any.
local function find_open_view(mode)
  local entries = require("trouble.view").get({ mode = mode, open = true })
  for i = #entries, 1, -1 do
    local view = entries[i].view
    if view and view.is_open and view:is_open() then
      return view
    end
  end
end

-- Opens `lsp` below the given symbols view (sidebar stack).
local function open_lsp_below(symbols_view)
  require("trouble").open({
    mode = "lsp",
    open_no_results = true,
    focus = false,
    win = { type = "split", relative = "win", win = symbols_view.win.win, position = "bottom", size = LSP_HEIGHT },
  })
end

local function toggle_symbols()
  local symbols_view = find_open_view("symbols")
  if symbols_view then
    symbols_view:close()
    return
  end

  -- If lsp is already open, stack symbols above it; otherwise use the right sidebar.
  local lsp_view = find_open_view("lsp")
  local win
  if lsp_view then
    win = { type = "split", relative = "win", win = lsp_view.win.win, position = "top", size = 0.5 }
  else
    win = { type = "split", relative = "editor", position = "right", size = SIDEBAR_WIDTH }
  end
  require("trouble").open({ mode = "symbols", open_no_results = true, focus = false, win = win })
end

local function toggle_lsp()
  local lsp_view = find_open_view("lsp")
  if lsp_view then
    lsp_view:close()
    return
  end

  -- lsp needs symbols as its anchor; open symbols first if it is not open.
  local symbols_view = find_open_view("symbols")
  if symbols_view then
    open_lsp_below(symbols_view)
    return
  end

  local anchor = require("trouble").open({
    mode = "symbols",
    open_no_results = true,
    focus = false,
    win = { type = "split", relative = "editor", position = "right", size = SIDEBAR_WIDTH },
  })
  if anchor then
    anchor:wait(function()
      if anchor:is_open() and not find_open_view("lsp") then
        open_lsp_below(anchor)
      end
    end)
  end
end

Snacks.keymap.set("n", "<leader>xx", function() require("trouble").toggle({ mode = "diagnostics" }) end, { desc = "Diagnostics (Trouble)" })
Snacks.keymap.set("n", "<leader>xX", function() require("trouble").toggle({ mode = "diagnostics", filter = { buf = 0 } }) end, { desc = "Buffer Diagnostics (Trouble)" })
Snacks.keymap.set("n", "<leader>cs", toggle_symbols, { desc = "Symbols (Trouble)" })
Snacks.keymap.set("n", "<leader>cS", toggle_lsp, { desc = "LSP references/definitions/... (Trouble)" })
Snacks.keymap.set("n", "<leader>xL", function() require("trouble").toggle({ mode = "loclist" }) end, { desc = "Location List (Trouble)" })
Snacks.keymap.set("n", "<leader>xQ", function() require("trouble").toggle({ mode = "qflist" }) end, { desc = "Quickfix List (Trouble)" })
Snacks.keymap.set("n", "[q", function()
  if require("trouble").is_open() then
    require("trouble").prev({ skip_groups = true, jump = true })
  else
    local ok, err = pcall(vim.cmd.cprev)
    if not ok then
      vim.notify(err, vim.log.levels.ERROR)
    end
  end
end, { desc = "Previous Trouble/Quickfix Item" })
Snacks.keymap.set("n", "]q", function()
  if require("trouble").is_open() then
    require("trouble").next({ skip_groups = true, jump = true })
  else
    local ok, err = pcall(vim.cmd.cnext)
    if not ok then
      vim.notify(err, vim.log.levels.ERROR)
    end
  end
end, { desc = "Next Trouble/Quickfix Item" })