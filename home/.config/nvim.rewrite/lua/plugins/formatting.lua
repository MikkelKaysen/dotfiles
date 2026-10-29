-- ---------------------------------------------------------------------------
-- Formatting + linting + tasks:
--   conform.nvim   — formatters (primary formatter in the util.format registry)
--   nvim-lint      — CLI linters (markdownlint)
--   overseer.nvim  — task list / task actions
-- ---------------------------------------------------------------------------

-- --- conform.nvim ---------------------------------------------------------------
local prettier_supported = {
  "css",
  "graphql",
  "handlebars",
  "html",
  "javascript",
  "javascriptreact",
  "json",
  "jsonc",
  "less",
  "markdown",
  "markdown.mdx",
  "scss",
  "typescript",
  "typescriptreact",
  "vue",
  "yaml",
}

-- prettier: only when it can infer a parser for the file
local function prettier_has_parser(ctx)
  local ft = vim.bo[ctx.buf].filetype
  if vim.tbl_contains(prettier_supported, ft) then
    return true
  end
  local ret = vim.fn.system({ "prettier", "--file-info", ctx.filename })
  local ok, parser = pcall(function()
    return vim.fn.json_decode(ret).inferredParser
  end)
  return ok and parser and parser ~= vim.NIL
end

local by_ft = {
  -- LazyVim core
  lua = { "stylua" },
  fish = { "fish_indent" },
  sh = { "shfmt" },
  -- prettier
  htmlangular = { "prettier" },
  -- markdown (overrides prettier's markdown entry)
  markdown = { "prettier", "markdownlint-cli2", "markdown-toc" },
  ["markdown.mdx"] = { "prettier", "markdownlint-cli2", "markdown-toc" },
}
for _, ft in ipairs(prettier_supported) do
  by_ft[ft] = by_ft[ft] or { "prettier" }
end

require("conform").setup({
  default_format_opts = {
    timeout_ms = 3000,
    async = false, -- not recommended to change
    quiet = false, -- not recommended to change
    lsp_format = "fallback", -- not recommended to change
  },
  formatters_by_ft = by_ft,
  formatters = {
    injected = { options = { ignore_errors = true } },
    prettier = { condition = function(_, ctx) return prettier_has_parser(ctx) end },
    ["markdown-toc"] = {
      condition = function(_, ctx)
        for _, line in ipairs(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)) do
          if line:find("<!%-%- toc %-%->") then
            return true
          end
        end
      end,
    },
    ["markdownlint-cli2"] = {
      condition = function(_, ctx)
        local diag = vim.tbl_filter(function(d)
          return d.source == "markdownlint"
        end, vim.diagnostic.get(ctx.buf))
        return #diag > 0
      end,
    },
  },
})

-- Register conform as the primary formatter for the util.format registry
require("util.format").register({
  name = "conform.nvim",
  priority = 100,
  primary = true,
  format = function(buf)
    require("conform").format({ bufnr = buf })
  end,
  sources = function(buf)
    return vim.tbl_map(function(v)
      return v.name
    end, require("conform").list_formatters(buf))
  end,
})

-- Format-on-save autocmd + :Format + :FormatInfo (util.format machinery)
require("util.format").setup()

-- Format injected languages
Snacks.keymap.set({ "n", "x" }, "<leader>cF", function()
  require("conform").format({ formatters = { "injected" }, timeout_ms = 3000 })
end, { desc = "Format Injected Langs" })

-- --- nvim-lint -------------------------------------------------------------------
-- Asynchronously runs CLI linters and reports results via vim.diagnostic.
local lint = require("lint")
lint.linters_by_ft = vim.tbl_extend("force", lint.linters_by_ft, {
  fish = { "fish" },
  markdown = { "markdownlint-cli2" },
})

local function debounce(ms, fn)
  local timer = vim.uv.new_timer()
  return function(...)
    local argv = { ... }
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule_wrap(fn)(unpack(argv))
    end)
  end
end

local function run_linters()
  -- nvim-lint's resolution: full filetype first, then split filetype parts;
  -- add "_" fallback and "*" global linters, then filter conditions.
  local names = lint._resolve_linter_by_ft(vim.bo.filetype)
  names = vim.list_extend({}, names)
  if #names == 0 then
    vim.list_extend(names, lint.linters_by_ft["_"] or {})
  end
  vim.list_extend(names, lint.linters_by_ft["*"] or {})
  local ctx = { filename = vim.api.nvim_buf_get_name(0) }
  ctx.dirname = vim.fn.fnamemodify(ctx.filename, ":h")
  names = vim.tbl_filter(function(name)
    local linter = lint.linters[name]
    if not linter then
      vim.notify("Linter not found: " .. name, vim.log.levels.WARN, { title = "nvim-lint" })
    end
    return linter and not (type(linter) == "table" and linter.condition and not linter.condition(ctx))
  end, names)
  if #names > 0 then
    lint.try_lint(names)
  end
end

vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
  group = vim.api.nvim_create_augroup("RewriteLint", { clear = true }),
  callback = debounce(100, run_linters),
})

-- --- overseer.nvim ------------------------------------------------------------------
-- Self-lazy-loading: the plugin file registers the Overseer* commands.
require("overseer").setup({
  dap = false,
  task_list = {
    keymaps = {
      ["<C-j>"] = false,
      ["<C-k>"] = false,
    },
  },
  form = {
    win_opts = {
      winblend = 0,
    },
  },
  task_win = {
    win_opts = {
      winblend = 0,
    },
  },
})

Snacks.keymap.set("n", "<leader>ow", "<cmd>OverseerToggle!<cr>", { desc = "Task list" })
Snacks.keymap.set("n", "<leader>oo", "<cmd>OverseerRun<cr>", { desc = "Run task" })
Snacks.keymap.set("n", "<leader>ot", "<cmd>OverseerTaskAction<cr>", { desc = "Task action" })
require("which-key").add({ { "<leader>o", group = "overseer" } }, { notify = false })