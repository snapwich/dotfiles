return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      vtsls = {
        keys = {
          { "<leader>co", false },
        }
      },
      -- Apply these keymaps to all LSP servers
      ["*"] = {
        keys = {
          -- Disable default Code Action and Source Action keymaps (conflict with diffview)
          { "<leader>ca", false },
          { "<leader>cA", false },

          -- Disable Codelens keymaps (unused)
          { "<leader>cc", false },
          { "<leader>cC", false },

          -- Add new Code Action keymap
          {
            "<leader>cc",
            vim.lsp.buf.code_action,
            desc = "Code Action",
            mode = { "n", "v" },
            has = "codeAction",
          },

          -- Add new Source Action keymap
          {
            "<leader>cC",
            function()
              vim.lsp.buf.code_action({
                context = {
                  only = { "source" },
                  diagnostics = {},
                },
              })
            end,
            desc = "Source Action",
            has = "codeAction",
          },
        },
      },
    },
  },
}
