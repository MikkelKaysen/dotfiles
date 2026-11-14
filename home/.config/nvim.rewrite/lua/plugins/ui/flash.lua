-- ---------------------------------------------------------------------------
-- flash (ported from LazyVim's editor.lua).
-- ---------------------------------------------------------------------------

require("flash").setup({})

-- stylua: ignore
Snacks.keymap.set({ "n", "x", "o" }, "s", function() require("flash").jump() end, { desc = "Flash" })
Snacks.keymap.set({ "n", "o", "x" }, "S", function() require("flash").treesitter() end, { desc = "Flash Treesitter" })
Snacks.keymap.set("o", "r", function() require("flash").remote() end, { desc = "Remote Flash" })
Snacks.keymap.set({ "o", "x" }, "R", function() require("flash").treesitter_search() end, { desc = "Treesitter Search" })
Snacks.keymap.set("c", "<c-s>", function() require("flash").toggle() end, { desc = "Toggle Flash Search" })
-- Simulate nvim-treesitter incremental selection
Snacks.keymap.set({ "n", "o", "x" }, "<c-space>", function()
  require("flash").treesitter({
    actions = {
      ["<c-space>"] = "next",
      ["<BS>"] = "prev",
    },
  })
end, { desc = "Treesitter Incremental Selection" })