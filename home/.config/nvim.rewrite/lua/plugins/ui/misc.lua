-- ---------------------------------------------------------------------------
-- misc (ported from LazyVim's editor.lua / coding.lua / util.lua / ui.lua +
-- the yanky / mini-animate / mini-surround extras): todo-comments,
-- ts-autotag, mini.pairs, mini.surround, mini.animate, mini.icons,
-- ts-comments, grug-far, persistence, yanky + snacks scratch keys.
-- ---------------------------------------------------------------------------

-- todo-comments
require("todo-comments").setup({})
Snacks.keymap.set("n", "]t", function() require("todo-comments").jump_next() end, { desc = "Next Todo Comment" })
Snacks.keymap.set("n", "[t", function() require("todo-comments").jump_prev() end, { desc = "Previous Todo Comment" })
Snacks.keymap.set("n", "<leader>xt", "<cmd>Trouble todo toggle<cr>", { desc = "Todo (Trouble)" })
Snacks.keymap.set("n", "<leader>xT", "<cmd>Trouble todo toggle filter = {tag = {TODO,FIX,FIXME}}<cr>", { desc = "Todo/Fix/Fixme (Trouble)" })

-- automatically add closing tags for HTML and JSX
require("nvim-ts-autotag").init()

-- mini.pairs (better auto-pairs; util.mini.pairs adds the toggle + open fix)
require("util.mini").pairs({
  modes = { insert = true, command = true, terminal = false },
  -- skip autopair when next character is one of these
  skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
  -- skip autopair when the cursor is inside these treesitter nodes
  skip_ts = { "string" },
  -- skip autopair when next character is closing pair
  -- and there are more closing pairs than opening pairs
  skip_unbalanced = true,
  -- better deal with markdown code blocks
  markdown = true,
})

-- mini.surround (gs* mappings; setup registers the keymaps)
require("mini.surround").setup({
  mappings = {
    add = "gsa", -- Add surrounding in Normal and Visual modes
    delete = "gsd", -- Delete surrounding
    find = "gsf", -- Find surrounding (to the right)
    find_left = "gsF", -- Find surrounding (to the left)
    highlight = "gsh", -- Highlight surrounding
    replace = "gsr", -- Replace surrounding
    update_n_lines = "gsn", -- Update `MiniSurround.config.n_lines`
  },
})

-- mini.animate (animations; from the mini-animate extra — it disables
-- snacks.scroll, which is set accordingly in plugins/picker.lua)
if vim.g.neovide == nil then
  -- don't use animate when scrolling with the mouse
  local mouse_scrolled = false
  for _, scroll in ipairs({ "Up", "Down" }) do
    local key = "<ScrollWheel" .. scroll .. ">"
    vim.keymap.set({ "", "i" }, key, function()
      mouse_scrolled = true
      return key
    end, { expr = true })
  end

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "grug-far",
    callback = function()
      vim.b.minianimate_disable = true
    end,
  })

  -- overrides <leader>ua (Snacks animate toggle) from config/keymaps.lua
  Snacks.toggle({
    name = "Mini Animate",
    get = function()
      return not vim.g.minianimate_disable
    end,
    set = function(state)
      vim.g.minianimate_disable = not state
    end,
  }):map("<leader>ua")

  local animate = require("mini.animate")
  animate.setup({
    resize = {
      timing = animate.gen_timing.linear({ duration = 50, unit = "total" }),
    },
    scroll = {
      timing = animate.gen_timing.linear({ duration = 150, unit = "total" }),
      subscroll = animate.gen_subscroll.equal({
        predicate = function(total_scroll)
          if mouse_scrolled then
            mouse_scrolled = false
            return false
          end
          return total_scroll > 1
        end,
      }),
    },
  })
end

-- mini.icons (nvim-web-devicons compatibility)
package.preload["nvim-web-devicons"] = function()
  require("mini.icons").mock_nvim_web_devicons()
  return package.loaded["nvim-web-devicons"]
end
require("mini.icons").setup({
  file = {
    [".keep"] = { glyph = "󰊢", hl = "MiniIconsGrey" },
    ["devcontainer.json"] = { glyph = "", hl = "MiniIconsAzure" },
  },
  filetype = {
    dotenv = { glyph = "", hl = "MiniIconsYellow" },
  },
})

-- ts-comments (improved comment syntax)
require("ts-comments").setup({})

-- grug-far (search/replace in multiple files)
require("grug-far").setup({ headerMaxWidth = 80 })
Snacks.keymap.set({ "n", "x" }, "<leader>sr", function()
  local grug = require("grug-far")
  local ext = vim.bo.buftype == "" and vim.fn.expand("%:e")
  grug.open({
    transient = true,
    prefills = {
      filesFilter = ext and ext ~= "" and "*." .. ext or nil,
    },
  })
end, { desc = "Search and Replace" })

-- persistence (session management)
require("persistence").setup({})
Snacks.keymap.set("n", "<leader>qs", function() require("persistence").load() end, { desc = "Restore Session" })
Snacks.keymap.set("n", "<leader>qS", function() require("persistence").select() end, { desc = "Select Session" })
Snacks.keymap.set("n", "<leader>ql", function() require("persistence").load({ last = true }) end, { desc = "Restore Last Session" })
Snacks.keymap.set("n", "<leader>qd", function() require("persistence").stop() end, { desc = "Don't Save Current Session" })

-- yanky (better yank/paste)
require("yanky").setup({
  system_clipboard = {
    sync_with_ring = not vim.env.SSH_CONNECTION,
  },
  highlight = { timer = 150 },
})
-- stylua: ignore
Snacks.keymap.set({ "n", "x" }, "<leader>p", function() Snacks.picker.yanky() end, { desc = "Open Yank History" })
Snacks.keymap.set({ "n", "x" }, "y", "<Plug>(YankyYank)", { desc = "Yank Text" })
Snacks.keymap.set({ "n", "x" }, "p", "<Plug>(YankyPutAfter)", { desc = "Put Text After Cursor" })
Snacks.keymap.set({ "n", "x" }, "P", "<Plug>(YankyPutBefore)", { desc = "Put Text Before Cursor" })
Snacks.keymap.set({ "n", "x" }, "gp", "<Plug>(YankyGPutAfter)", { desc = "Put Text After Selection" })
Snacks.keymap.set({ "n", "x" }, "gP", "<Plug>(YankyGPutBefore)", { desc = "Put Text Before Selection" })
Snacks.keymap.set("n", "[y", "<Plug>(YankyCycleForward)", { desc = "Cycle Forward Through Yank History" })
Snacks.keymap.set("n", "]y", "<Plug>(YankyCycleBackward)", { desc = "Cycle Backward Through Yank History" })
Snacks.keymap.set("n", "]p", "<Plug>(YankyPutIndentAfterLinewise)", { desc = "Put Indented After Cursor (Linewise)" })
Snacks.keymap.set("n", "[p", "<Plug>(YankyPutIndentBeforeLinewise)", { desc = "Put Indented Before Cursor (Linewise)" })
Snacks.keymap.set("n", "]P", "<Plug>(YankyPutIndentAfterLinewise)", { desc = "Put Indented After Cursor (Linewise)" })
Snacks.keymap.set("n", "[P", "<Plug>(YankyPutIndentBeforeLinewise)", { desc = "Put Indented Before Cursor (Linewise)" })
Snacks.keymap.set("n", ">p", "<Plug>(YankyPutIndentAfterShiftRight)", { desc = "Put and Indent Right" })
Snacks.keymap.set("n", "<p", "<Plug>(YankyPutIndentAfterShiftLeft)", { desc = "Put and Indent Left" })
Snacks.keymap.set("n", ">P", "<Plug>(YankyPutIndentBeforeShiftRight)", { desc = "Put Before and Indent Right" })
Snacks.keymap.set("n", "<P", "<Plug>(YankyPutIndentBeforeShiftLeft)", { desc = "Put Before and Indent Left" })
Snacks.keymap.set("n", "=p", "<Plug>(YankyPutAfterFilter)", { desc = "Put After Applying a Filter" })
Snacks.keymap.set("n", "=P", "<Plug>(YankyPutBeforeFilter)", { desc = "Put Before Applying a Filter" })

-- snacks scratch buffer
Snacks.keymap.set("n", "<leader>.", function() Snacks.scratch() end, { desc = "Toggle Scratch Buffer" })
Snacks.keymap.set("n", "<leader>S", function() Snacks.scratch.select() end, { desc = "Select Scratch Buffer" })
Snacks.keymap.set("n", "<leader>dps", function() Snacks.profiler.scratch() end, { desc = "Profiler Scratch Buffer" })