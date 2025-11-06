return {
  {
    "rachartier/tiny-inline-diagnostic.nvim",
    event = "VeryLazy",
    priority = 1000,
    opts = {
      options = {
        show_all_diags_on_cursorline = true,
        override_open_float = true,
        show_source = {
          enabled = true,
        },
        add_messages = {
          display_count = true,
        },
        multilines = {
          enabled = true,
          always_show = true,
        }
      }
    },
    keys = {
      { "]d", function() vim.diagnostic.jump({ count = 1, float = false }) end,                                            desc = "Next Diagnostic" },
      { "[d", function() vim.diagnostic.jump({ count = -1, float = false }) end,                                           desc = "Prev Diagnostic" },
      { "]e", function() vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR, float = false }) end,  desc = "Next Error" },
      { "[e", function() vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR, float = false }) end, desc = "Prev Error" },
      { "]w", function() vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.WARN, float = false }) end,   desc = "Next Warning" },
      { "[w", function() vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.WARN, float = false }) end,  desc = "Prev Warning" },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        virtual_text = false,
      }
    },
  },
}
