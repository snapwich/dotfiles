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
