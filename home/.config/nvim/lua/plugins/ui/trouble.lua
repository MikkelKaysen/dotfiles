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
    symbols_lsp = {
      sections = {
        "symbols",
        "lsp_definitions",
        "lsp_references",
        "lsp_implementations",
        "lsp_type_definitions",
        "lsp_declarations",
        "lsp_incoming_calls",
        "lsp_outgoing_calls",
      },
      win = { type = "split", position = "right", size = 40 },
      focus = false,
    },
  },
})

Snacks.keymap.set("n", "<leader>xx", function() require("trouble").toggle({ mode = "diagnostics" }) end, { desc = "Diagnostics (Trouble)" })
Snacks.keymap.set("n", "<leader>xX", function() require("trouble").toggle({ mode = "diagnostics", filter = { buf = 0 } }) end, { desc = "Buffer Diagnostics (Trouble)" })
Snacks.keymap.set("n", "<leader>cs", function() require("trouble").open({ mode = "symbols_lsp" }) end, { desc = "Symbols (Trouble)" })
Snacks.keymap.set("n", "<leader>cS", function() require("trouble").open({ mode = "symbols_lsp" }) end, { desc = "LSP references/definitions/... (Trouble)" })
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