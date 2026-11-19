-- ---------------------------------------------------------------------------
-- trouble (ported from LazyVim's editor.lua).
-- NOTE: [q/]q are re-registered here so they win over config/keymaps.lua —
-- same ordering as LazyVim's lazy.nvim key registration.
-- ---------------------------------------------------------------------------

require("trouble").setup({
  modes = {
    lsp = {
      win = { position = "right" },
    },
  },
})

Snacks.keymap.set("n", "<leader>xx", function() require("trouble").toggle({ mode = "diagnostics" }) end, { desc = "Diagnostics (Trouble)" })
Snacks.keymap.set("n", "<leader>xX", function() require("trouble").toggle({ mode = "diagnostics", filter = { buf = 0 } }) end, { desc = "Buffer Diagnostics (Trouble)" })
Snacks.keymap.set("n", "<leader>cs", function() require("trouble").toggle({ mode = "symbols" }) end, { desc = "Symbols (Trouble)" })
Snacks.keymap.set("n", "<leader>cS", function() require("trouble").toggle({ mode = "lsp" }) end, { desc = "LSP references/definitions/... (Trouble)" })
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