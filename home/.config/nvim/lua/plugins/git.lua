return {
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
      "nvim-telescope/telescope.nvim",
    },
    opts = {},
    keys = {
      { "<leader>gG", "<cmd>Neogit<cr>", desc = "Neogit (cwd)" },
      {
        "<leader>gg",
        function()
          local neogit = require("neogit")

          neogit.open({ cwd = LazyVim.root.get() })
        end,
        desc = "Neogit (cwd)",
      },
    },
  },
  {
    "polarmutex/git-worktree.nvim",
    version = "^2",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
    },
    keys = {
      {
        "<leader>gw",
        function()
          local telescope = require("telescope")

          telescope.extensions.git_worktree.git_worktree()
        end,
        desc = "Git Worktree (select)",
      },
      {
        "<leader>gW",
        function()
          local telescope = require("telescope")

          telescope.extensions.git_worktree.create_git_worktree()
        end,
        desc = "Git Worktree (create)",
      },
    },
    init = function()
      require("telescope").load_extension("git_worktree")
    end,
  },
}
