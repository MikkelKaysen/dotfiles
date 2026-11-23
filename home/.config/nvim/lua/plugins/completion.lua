-- ---------------------------------------------------------------------------
-- Completion: blink.cmp v2 (main; needs saghen/blink.lib) + LuaSnip +
-- friendly-snippets (ported from LazyVim's blink + luasnip extras).
-- Deferred to the first InsertEnter/CmdlineEnter.
-- The Rust fuzzy library is built once with `require('blink.cmp').build():pwait()`
-- (vim.pack has no build hook); see :checkhealth blink.cmp.
-- org.nvim's blink source ("Org") is enabled for org buffers only.
-- ---------------------------------------------------------------------------

local function setup_completion()
  if package.loaded["rewrite_completion"] then
    return
  end

  -- blink.cmp v2 depends on blink.lib: it must be on the rtp before blink.cmp
  local ok_lib, lib_err = pcall(require, "blink.lib")
  if not ok_lib then
    vim.notify("blink.cmp v2 needs saghen/blink.lib: " .. tostring(lib_err), vim.log.levels.ERROR)
    return
  end

  -- LuaSnip
  require("luasnip").setup({
    history = true,
    delete_check_events = "TextChanged",
  })
  require("luasnip.loaders.from_vscode").lazy_load()
  require("luasnip.loaders.from_vscode").lazy_load({
    paths = { vim.fn.stdpath("config") .. "/snippets" },
  })

  -- blink.cmp
  local opts = {
    snippets = {
      preset = "luasnip",
    },
    appearance = {
      -- sets the fallback highlight groups to nvim-cmp's highlight groups
      use_nvim_cmp_as_default = false,
      -- set to 'mono' for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
      nerd_font_variant = "mono",
      kind_icons = require("util.icons").icons.kinds,
    },
    completion = {
      accept = {
        -- experimental auto-brackets support
        auto_brackets = {
          enabled = true,
        },
      },
      menu = {
        draw = {
          treesitter = { "lsp" },
        },
      },
      documentation = {
        auto_show = true,
        auto_show_delay_ms = 200,
      },
      ghost_text = {
        enabled = vim.g.ai_cmp,
      },
    },
    sources = {
      default = { "lsp", "path", "snippets", "buffer" },
      -- org.nvim's blink source (module org.completion.blink, enabled for org only)
      per_filetype = {
        org = { inherit_defaults = true, "org" },
      },
      providers = {
        org = { name = "Org", module = "org.completion.blink" },
      },
    },
    cmdline = {
      enabled = true,
      keymap = {
        preset = "cmdline",
        ["<Right>"] = false,
        ["<Left>"] = false,
      },
      completion = {
        list = { selection = { preselect = false } },
        menu = {
          auto_show = function()
            return vim.fn.getcmdtype() == ":"
          end,
        },
        ghost_text = { enabled = true },
      },
    },
    keymap = {
      preset = "enter",
      ["<C-y>"] = { "select_and_accept" },
    },
  }

  require("blink.cmp").setup(opts)
  package.loaded["rewrite_completion"] = true
end

vim.api.nvim_create_autocmd({ "InsertEnter", "CmdlineEnter" }, {
  group = vim.api.nvim_create_augroup("rewrite_completion", { clear = true }),
  callback = setup_completion,
})
