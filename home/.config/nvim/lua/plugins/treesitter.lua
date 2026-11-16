-- ---------------------------------------------------------------------------
-- nvim-treesitter (main branch) + textobjects
-- (ported from LazyVim's treesitter.lua, using util.treesitter helpers).
-- ---------------------------------------------------------------------------

local TS = require("nvim-treesitter")

-- Neorg grammars are not in the upstream main-branch registry, so they are
-- added to the parsers table here (a plain table returned by
-- nvim-treesitter.parsers). Pinned to the tags Neorg v9.6.4 expects.
-- Requires a C++ compiler (norg's scanner.cc). Re-applied after TSUpdate,
-- because a parser update may rebuild that table.
local function register_neorg_parsers()
  local parsers = require("nvim-treesitter.parsers")
  parsers.norg = {
    install_info = {
      url = "https://github.com/nvim-neorg/tree-sitter-norg",
      revision = "aa1a1a7ded81a094cc3d5cb14bea6f34b86d8688", -- tag v0.2.4
    },
    tier = 2,
  }
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
    "diff",
    "html",
    "javascript",
    "jsdoc",
    "json",
    "json5",
    "lua",
    "luadoc",
    "luap",
    "markdown",
    "markdown_inline",
    "norg",
    "norg_meta",
    "printf",
    "python",
    "query",
    "regex",
    "scss",
    "toml",
    "tsx",
    "typescript",
    "vim",
    "vimdoc",
    "xml",
    "yaml",
  },
}

TS.setup(opts)
require("util.treesitter").get_installed(true)

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