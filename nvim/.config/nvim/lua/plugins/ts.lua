return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      vtsls = {
        root_dir = require("lspconfig.util").root_pattern("pnpm-workspace.yaml")
            or require("lspconfig.util").root_pattern("pnpm-lock.yaml")
            or require("lspconfig.util").root_pattern(".git"),
      }
    }
  }
}
