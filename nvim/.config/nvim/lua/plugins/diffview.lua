return {
  "sindrets/diffview.nvim",
  keys = {
    { "<leader>dd", "<cmd>DiffviewOpen<cr>",          desc = "Diffview: open (working tree changes)" },
    { "<leader>dh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: file history (current)" },
    { "<leader>dH", "<cmd>DiffviewFileHistory<cr>",   desc = "Diffview: file history (all)" },
  },
  opts = {},
  lazy = false,
}
