return {
  "sindrets/diffview.nvim",
  keys = {
    { "<leader>dd", "<cmd>DiffviewOpen<cr>",          desc = "Diffview: open (working tree changes)" },
    { "<leader>dh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: file history (current)" },
    { "<leader>dH", "<cmd>DiffviewFileHistory<cr>",   desc = "Diffview: file history (all)" },
    {
      "<leader>dm",
      function()
        -- Check if origin/main exists, otherwise use origin/master
        local handle = io.popen("git rev-parse --verify origin/main 2>/dev/null")
        local default_branch = "master"

        if handle then
          local result = handle:read("*a")
          handle:close()
          if result and result ~= "" then
            default_branch = "main"
          end
        end

        vim.cmd("DiffviewOpen origin/" .. default_branch .. "...HEAD")
      end,
      desc = "Diffview: branch changes from origin/main or origin/master",
    },
  },
  opts = {},
  lazy = false,
}
