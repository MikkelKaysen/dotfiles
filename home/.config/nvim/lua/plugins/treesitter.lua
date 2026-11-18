-- ---------------------------------------------------------------------------
-- nvim-treesitter (main branch) + textobjects
-- (ported from LazyVim's treesitter.lua, using util.treesitter helpers).
-- ---------------------------------------------------------------------------

local TS = require("nvim-treesitter")

-- Neorg grammars are not in the upstream main-branch registry. norg_meta is registered
-- here (native install, pinned). The norg parser itself is built by util/norg_parser.lua
-- from a pinned commit. Its registry entry is query-only (tier 2, no install_info): the
-- custom builder owns the binary, Neorg owns the queries, and nvim-treesitter never tries
-- to compile or update it natively (so update/needs_update cannot log "parser not available").
-- Re-applied after TSUpdate, because a parser update may rebuild that table.
local function register_neorg_parsers()
  local parsers = require("nvim-treesitter.parsers")
  parsers.norg = { tier = 2 } -- query-only: no install_info (custom builder owns norg.so)
  parsers.norg_meta = {
    install_info = {
      url = "https://github.com/nvim-neorg/tree-sitter-norg-meta",
      revision = "6f0510cc516a3af3396a682fbd6655486c2c9d2d", -- tag v0.1.0
    },
    tier = 2,
  }
end
register_neorg_parsers()
vim.api.nvim_create_autocmd("User", {
  pattern = "TSUpdate",
  group = vim.api.nvim_create_augroup("neorg_parser_registry", { clear = true }),
  callback = register_neorg_parsers,
})

local opts = {
  indent = { enable = true },
  highlight = { enable = true },
  folds = { enable = true },
  ensure_installed = {
    "angular",
    "bash",
    "c",
    "css",
    "diff",
    "html",
    "javascript",
    "jsdoc",
    "json",
    "json5",
    "latex",
    "lua",
    "luadoc",
    "luap",
    "markdown",
    "markdown_inline",
    "norg_meta",
    "printf",
    "python",
    "query",
    "regex",
    "scss",
    "toml",
    "tsx",
    "typescript",
    "typst",
    "vim",
    "vimdoc",
    "xml",
    "yaml",
  },
}

TS.setup(opts)
require("util.treesitter").get_installed(true)
-- Custom norg parser: builds in the background only when missing or outdated.
require("util.norg_parser").setup()

-- Angular: use the angular parser for component templates
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  pattern = { "*.component.html", "*.container.html" },
  callback = function()
    vim.treesitter.start(nil, "angular")
  end,
})

-- install missing parsers (deferred: the tree-sitter CLI may need a mason
-- download, and a failure there must not abort init.lua)
local install = vim.tbl_filter(function(lang)
  return not require("util.treesitter").have(lang)
end, opts.ensure_installed)
if #install > 0 then
  vim.schedule(function()
    require("util.treesitter").build(function()
      TS.install(install, { summary = true }):await(function()
        require("util.treesitter").get_installed(true) -- refresh the installed langs
      end)
    end)
  end)
end

-- per-filetype wiring
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("rewrite_treesitter", { clear = true }),
  callback = function(ev)
    local ft, lang = ev.match, vim.treesitter.language.get_lang(ev.match)
    if not require("util.treesitter").have(ft) then
      return
    end

    ---@param feat string
    ---@param query string
    local function enabled(feat, query)
      local f = opts[feat] or {}
      return f.enable ~= false
        and not (type(f.disable) == "table" and vim.tbl_contains(f.disable, lang))
        and require("util.treesitter").have(ft, query)
    end

    -- highlighting
    if enabled("highlight", "highlights") then
      pcall(vim.treesitter.start, ev.buf)
    end

    -- indents
    if enabled("indent", "indents") then
      vim.opt.indentexpr = "v:lua.require('util.treesitter').indentexpr()"
    end

    -- folds
    if enabled("folds", "folds") then
      if vim.o.foldmethod == "manual" or vim.o.foldmethod == "indent" then
        vim.opt.foldmethod = "expr"
        vim.opt.foldexpr = "v:lua.require('util.treesitter').foldexpr()"
      end
    end
  end,
})

-- textobjects
local TO = require("nvim-treesitter-textobjects")

local to_opts = {
  move = {
    enable = true,
    set_jumps = true, -- whether to set jumps in the jumplist
    -- LazyVim extension to create buffer-local keymaps
    keys = {
      goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer", ["]a"] = "@parameter.inner" },
      goto_next_end = { ["]F"] = "@function.outer", ["]C"] = "@class.outer", ["]A"] = "@parameter.inner" },
      goto_previous_start = { ["[f"] = "@function.outer", ["[c"] = "@class.outer", ["[a"] = "@parameter.inner" },
      goto_previous_end = { ["[F"] = "@function.outer", ["[C"] = "@class.outer", ["[A"] = "@parameter.inner" },
    },
  },
}

TO.setup(to_opts)

local function attach(buf)
  local ft = vim.bo[buf].filetype
  if not (vim.tbl_get(to_opts, "move", "enable") and require("util.treesitter").have(ft, "textobjects")) then
    return
  end
  ---@type table<string, table<string, string>>
  local moves = vim.tbl_get(to_opts, "move", "keys") or {}

  for method, keymaps in pairs(moves) do
    for key, query in pairs(keymaps) do
      local queries = type(query) == "table" and query or { query }
      local parts = {}
      for _, q in ipairs(queries) do
        local part = q:gsub("@", ""):gsub("%..*", "")
        part = part:sub(1, 1):upper() .. part:sub(2)
        table.insert(parts, part)
      end
      local desc = table.concat(parts, " or ")
      desc = (key:sub(1, 1) == "[" and "Prev " or "Next ") .. desc
      desc = desc .. (key:sub(2, 2) == key:sub(2, 2):upper() and " End" or " Start")
      vim.keymap.set({ "n", "x", "o" }, key, function()
        if vim.wo.diff and key:find("[cC]") then
          return vim.cmd("normal! " .. key)
        end
        require("nvim-treesitter-textobjects.move")[method](query, "textobjects")
      end, {
        buffer = buf,
        desc = desc,
        silent = true,
      })
    end
  end
end

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("rewrite_treesitter_textobjects", { clear = true }),
  callback = function(ev)
    attach(ev.buf)
  end,
})
vim.tbl_map(attach, vim.api.nvim_list_bufs())
