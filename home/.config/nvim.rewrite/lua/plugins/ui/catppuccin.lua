-- ---------------------------------------------------------------------------
-- catppuccin — the only colorscheme (tokyonight dropped).
-- ---------------------------------------------------------------------------

require("catppuccin").setup({
  lsp_styles = {
    underlines = {
      errors = { "undercurl" },
      hints = { "undercurl" },
      warnings = { "undercurl" },
      information = { "undercurl" },
    },
  },
  integrations = {
    blink_cmp = true,
    flash = true,
    grug_far = true,
    gitsigns = true,
    lsp_trouble = true,
    mason = true,
    mini = true,
    noice = true,
    overseer = true,
    snacks = true,
    which_key = true,
  },
})

vim.cmd.colorscheme("catppuccin")