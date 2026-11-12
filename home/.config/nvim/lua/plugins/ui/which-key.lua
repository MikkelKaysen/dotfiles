-- ---------------------------------------------------------------------------
-- which-key (ported from LazyVim's editor.lua).
-- ---------------------------------------------------------------------------

local wk = require("which-key")

wk.setup({
  preset = "helix",
  spec = {
    {
      mode = { "n", "x" },
      { "<leader><tab>", group = "tabs" },
      { "<leader>c", group = "code" },
      { "<leader>d", group = "debug" },
      { "<leader>dp", group = "profiler" },
      { "<leader>f", group = "file/find" },
      { "<leader>g", group = "git" },
      { "<leader>gh", group = "hunks" },
      { "<leader>q", group = "quit/session" },
      { "<leader>s", group = "search" },
      { "<leader>u", group = "ui" },
      { "<leader>x", group = "diagnostics/quickfix" },
      { "[", group = "prev" },
      { "]", group = "next" },
      { "g", group = "goto" },
      { "gr", group = "lsp refs/actions" },
      { "gs", group = "surround" },
      { "z", group = "fold" },
      {
        "<leader>b",
        group = "buffer",
        expand = function()
          return require("which-key.extras").expand.buf()
        end,
      },
      {
        "<leader>w",
        group = "windows",
        proxy = "<c-w>",
        expand = function()
          return require("which-key.extras").expand.win()
        end,
      },
      -- better descriptions
      { "gx", desc = "Open with system app" },
    },
    -- native Neovim 0.12 LSP defaults (description-only; mappings are not redefined)
    { "grn", desc = "Rename", mode = "n" },
    { "gra", desc = "Code Action", mode = { "n", "x" } },
    { "grr", desc = "References", mode = "n" },
    { "gri", desc = "Goto Implementation", mode = "n" },
    { "grt", desc = "Goto Type Definition", mode = "n" },
    { "grx", desc = "Run Codelens", mode = "n" },
    { "gO", desc = "Document Symbols", mode = "n" },
    { "<C-s>", desc = "Signature Help", mode = "i" },
  },
})

-- buffer keymaps
Snacks.keymap.set("n", "<leader>?", function()
  require("which-key").show({ global = false })
end, { desc = "Buffer Keymaps (which-key)" })

-- window hydra
Snacks.keymap.set("n", "<c-w><space>", function()
  require("which-key").show({ keys = "<c-w>", loop = true })
end, { desc = "Window Hydra Mode (which-key)" })