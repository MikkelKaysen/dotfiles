-- ---------------------------------------------------------------------------
-- snacks.nvim — the core UI layer: notifier, scope, input, words, toggle,
-- indent, scroll, bigfile, quickfile, terminal, dashboard (starter) + the
-- picker (replaces telescope).
-- Must be required before other plugin modules that use `Snacks.*`.
-- Ported from LazyVim's core snacks config (ui.lua + util.lua) + the
-- `snacks_picker` extra (picker opts/actions) + the dashboard preset
-- (minus the Lazy/LazyExtras keys, plus the Projects key).
-- ---------------------------------------------------------------------------

local Snacks = require("snacks")

-- Terminal Mappings
local function term_nav(dir)
  ---@param self snacks.terminal
  return function(self)
    return self:is_floating() and "<c-" .. dir .. ">" or vim.schedule(function()
      vim.cmd.wincmd(dir)
    end)
  end
end

-- snacks' dashboard "startup" section calls require("lazy.stats") — a lazy.nvim
-- module that doesn't exist under vim.pack. Provide a stand-in with real numbers.
package.preload["lazy.stats"] = function()
  local pack = require("pack") -- already required by init.lua; returns cached module
  return {
    stats = function()
      local count = #pack.plugins
      return { startuptime = (vim.uv.hrtime() - pack.start) / 1e9, loaded = count, count = count }
    end,
  }
end

Snacks.setup({
  bigfile = { enabled = true },
  indent = { enabled = true },
  input = { enabled = true },
  notifier = { enabled = true },
  quickfile = { enabled = true },
  scope = { enabled = true },
  scroll = { enabled = false }, -- disabled: mini.animate handles scroll animation
  statuscolumn = { enabled = false }, -- set in config/options.lua
  terminal = {
    win = {
      keys = {
        nav_h = { "<C-h>", term_nav("h"), desc = "Go to Left Window", expr = true, mode = "t" },
        nav_j = { "<C-j>", term_nav("j"), desc = "Go to Lower Window", expr = true, mode = "t" },
        nav_k = { "<C-k>", term_nav("k"), desc = "Go to Upper Window", expr = true, mode = "t" },
        nav_l = { "<C-l>", term_nav("l"), desc = "Go to Right Window", expr = true, mode = "t" },
        hide_slash = { "<C-/>", "hide", desc = "Hide Terminal", mode = "t" },
        hide_underscore = { "<c-_>", "hide", desc = "which_key_ignore", mode = "t" },
      },
    },
  },
  toggle = { map = Snacks.keymap.set },
  words = { enabled = true },
  dashboard = {
    preset = {
      pick = function(cmd, opts)
        return require("util.pick")(cmd, opts)()
      end,
      -- stylua: ignore
      ---@type snacks.dashboard.Item[]
      keys = {
        { icon = "", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
        { icon = "", key = "n", desc = "New File", action = ":ene | startinsert" },
        { icon = "", key = "p", desc = "Projects", action = ":lua Snacks.picker.projects()" },
        { icon = "", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
        { icon = "", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
        { icon = "", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
        { icon = "", key = "s", desc = "Restore Session", action = ":lua require('persistence').load()" },
        { icon = "", key = "q", desc = "Quit", action = ":qa" },
      },
    },
  },
  explorer = { enabled = true },
  picker = {
    win = {
      input = {
        keys = {
          ["<a-c>"] = {
            "toggle_cwd",
            mode = { "n", "i" },
          },
          ["<a-t>"] = {
            "trouble_open",
            mode = { "n", "i" },
          },
          ["<a-s>"] = { "flash", mode = { "n", "i" } },
          ["s"] = { "flash" },
        },
      },
    },
    actions = {
      ---@param p snacks.Picker
      toggle_cwd = function(p)
        local root = require("util.root")({ buf = p.input.filter.current_buf, normalize = true })
        local cwd = vim.fs.normalize((vim.uv or vim.loop).cwd() or ".")
        local current = p:cwd()
        p:set_cwd(current == root and cwd or root)
        p:find()
      end,
      trouble_open = function(...)
        return require("trouble.sources.snacks").actions.trouble_open.action(...)
      end,
      ---@param picker snacks.Picker
      flash = function(picker)
        require("flash").jump({
          pattern = "^",
          label = { after = { 0, 0 } },
          search = {
            mode = "search",
            exclude = {
              function(win)
                return vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "snacks_picker_list"
              end,
            },
          },
          action = function(match)
            local idx = picker.list:row2idx(match.pos[1])
            picker.list:_move(idx, true, true)
          end,
        })
      end,
    },
  },
})

-- file explorer (snacks explorer — a picker in disguise)
Snacks.keymap.set("n", "<leader>fe", function() Snacks.explorer({ cwd = require("util.root")() }) end, { desc = "File Explorer (Root Dir)" })
Snacks.keymap.set("n", "<leader>fE", function() Snacks.explorer() end, { desc = "File Explorer (cwd)" })
Snacks.keymap.set("n", "<leader>e", "<leader>fe", { desc = "File Explorer (Root Dir)", remap = true })
Snacks.keymap.set("n", "<leader>E", "<leader>fE", { desc = "File Explorer (cwd)", remap = true })