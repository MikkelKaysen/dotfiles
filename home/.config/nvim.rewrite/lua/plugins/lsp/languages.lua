-- ---------------------------------------------------------------------------
-- Per-language LSP servers + language editor extras.
--
-- Base server configs come for free from nvim-lspconfig's `lsp/<name>.lua`
-- files (auto-loaded by `vim.lsp.config` from the runtimepath); here we
-- only add per-language overrides.
--
-- Enabling: no explicit `vim.lsp.enable` here — mason-lspconfig
-- (plugins/lsp/mason.lua) enables each server automatically once its mason
-- package is installed (already-installed at setup + install:success).
-- ---------------------------------------------------------------------------

-- --- TypeScript (ts_ls) + Angular -------------------------------------------
-- @angular/language-server as a tsserver global plugin (mason package
-- "angular-language-server"). Only wired up once the package exists; on a
-- first run it is installed by mason and applies from the next start.
local angular_plugin =
  vim.fn.stdpath("data") .. "/mason/packages/angular-language-server/node_modules/@angular/language-server"
if vim.fn.isdirectory(angular_plugin) == 1 then
  vim.lsp.config("ts_ls", {
    init_options = {
      globalPlugins = {
        {
          name = "@angular/language-server",
          location = angular_plugin,
          enableForWorkspaceTypeScriptVersions = false,
        },
      },
    },
  })
end

-- angularls: disable renaming (HACK: duplicate rename popups, from LazyVim)
Snacks.util.lsp.on({ name = "angularls" }, function(_, client)
  client.server_capabilities.renameProvider = false
end)

-- --- JSON (jsonls + SchemaStore.nvim) ----------------------------------------
vim.lsp.config("jsonls", {
  before_init = function(_, config)
    config.settings = config.settings or {}
    config.settings.json = config.settings.json or {}
    config.settings.json.schemas = config.settings.json.schemas or {}
    vim.list_extend(config.settings.json.schemas, require("schemastore").json.schemas())
  end,
  settings = {
    json = {
      format = { enable = true },
      validate = { enable = true },
    },
  },
})

-- --- YAML (yamlls + SchemaStore.nvim) -----------------------------------------
vim.lsp.config("yamlls", {
  -- required for yamlls to know we support line folding
  capabilities = {
    textDocument = {
      foldingRange = {
        dynamicRegistration = false,
        lineFoldingOnly = true,
      },
    },
  },
  before_init = function(_, config)
    config.settings = config.settings or {}
    config.settings.yaml = config.settings.yaml or {}
    config.settings.yaml.schemas = vim.tbl_deep_extend(
      "force",
      config.settings.yaml.schemas or {},
      require("schemastore").yaml.schemas()
    )
  end,
  settings = {
    yaml = {
      keyOrdering = false,
      validate = true,
      schemaStore = {
        -- the server's built-in schemaStore must be disabled to use the plugin's
        enable = false,
        -- avoids `TypeError: Cannot read properties of undefined (reading 'length')`
        url = "",
      },
    },
  },
})

-- --- Markdown ------------------------------------------------------------------
vim.filetype.add({
  extension = { mdx = "markdown.mdx" },
})

-- render-markdown: nicer markdown rendering
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "norg", "rmd", "org", "codecompanion" },
  callback = function()
    require("render-markdown").setup({
      code = {
        sign = false,
        width = "block",
        right_pad = 1,
      },
      heading = {
        sign = false,
        icons = {},
      },
      checkbox = {
        enabled = false,
      },
    })
  end,
})
Snacks.toggle({
  name = "Render Markdown",
  get = require("render-markdown").get,
  set = require("render-markdown").set,
}):map("<leader>um")

-- markdown-preview (mkdp): the plugin file registers the MarkdownPreview* commands
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.keymap.set("n", "<leader>cp", "<cmd>MarkdownPreviewToggle<cr>", { desc = "Markdown Preview", buffer = true })
  end,
})
-- one-time prebuilt binary download (self-guarding: no-op if already installed)
vim.schedule(function()
  local ok = pcall(function()
    if vim.fn["mkdp#util#pre_build_version"]() == "" then
      vim.fn["mkdp#util#install"](true)
    end
  end)
  if not ok then
    vim.notify("markdown-preview.nvim: install check failed", vim.log.levels.WARN)
  end
end)

-- --- ESLint ---------------------------------------------------------------------
-- The eslint LSP formatter: non-primary, registered behind conform so the
-- eslint server's formatting is available (same behavior as LazyVim's
-- linting.eslint extra).
require("util.format").register(require("util.lsp").formatter({
  name = "eslint: lsp",
  priority = 200,
  filter = "eslint",
}))

-- TOML (taplo), Markdown (marksman) and Python (pyright) need no overrides;
-- the nvim-lspconfig `lsp/*.lua` configs are used as-is.